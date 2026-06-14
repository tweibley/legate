# File: lib/legate/session.rb
# frozen_string_literal: true

require 'concurrent'
require 'securerandom'
require 'json'
require_relative 'event' # Require the new Event class
require_relative 'errors'

module Legate
  # Represents a single, ongoing conversation thread between a user and an agent system.
  # It holds the history of interactions (Events) and temporary session-specific data (State).
  class Session
    VALID_PREFIXES = %w[user app temp].freeze

    attr_reader :id, :app_name, :user_id, :created_at
    attr_accessor :updated_at, :session_service

    # Initializes a new session. Typically called by a SessionService.
    # @param id [String] A unique identifier for the session (defaults to UUID).
    # @param app_name [String] Identifier for the agent application.
    # @param user_id [String] Identifier for the user initiating the session.
    # @param initial_state [Hash] Optional initial data for the session state. Keys are symbolized.
    # @param events [Array<Legate::Event>] Optional initial list of events (for reloading).
    # @param session_service [Legate::SessionService::Base] The session service to use for persistence
    def initialize(app_name:, user_id:, id: nil, initial_state: {}, events: [], session_service: nil)
      @id = id || SecureRandom.uuid
      @app_name = app_name
      @user_id = user_id
      @created_at = Time.now.utc # Use UTC
      @updated_at = @created_at
      @session_service = session_service
      @mutex = Mutex.new
      # Use Concurrent::Map for thread-safe state storage within the session object itself
      @state = Concurrent::Map.new
      # Ensure initial_state keys are symbols and manually populate the map
      initial_state = {} unless initial_state.is_a?(Hash) # Ensure it's a hash
      symbolized_initial_state = initial_state.transform_keys { |k|
        begin
          k.to_sym
        rescue StandardError
          k
        end
      }
      symbolized_initial_state.each_pair do |key, value|
        @state[key] = value
      end
      # Events array stores the history, ensure it's mutable if passed and validate contents
      @events = events.map do |e|
        if e.is_a?(Legate::Event)
          e
        else
          (Legate.logger.warn("Session Init: Invalid event data skipped: #{e.inspect}")
           nil)
        end
      end.compact
      Legate.logger.debug("Session initialized: id=#{@id}, app=#{@app_name}, user=#{@user_id}, event_count=#{@events.size}")
    end

    # Thread-safe accessor for session events.
    # @return [Array<Legate::Event>] A frozen snapshot of the event history.
    def events
      @mutex.synchronize { @events.dup.freeze }
    end

    # Provides access to the session's temporary state data.
    # @return [Hash] The current session state (immutable view).
    def state
      # Ensure external modifications don't affect internal state directly.
      @state.dup # Return a shallow copy
    end

    # Adds an event to the session's history and updates state if needed.
    # @param event [Legate::Event] The event to add
    # @return [Legate::Event, nil] The added event or nil if invalid
    def add_event(event)
      return nil unless event.is_a?(Legate::Event)

      @mutex.synchronize do
        @events << event
        @updated_at = Time.now.utc
      end

      # Apply the event's state delta OUTSIDE the mutex: update_state may call the
      # session service (save_scoped_state), and holding the non-reentrant @mutex
      # across that external call risks deadlock if a service implementation calls
      # back into the session (e.g. #events/#to_h). @state is a Concurrent::Map, so
      # it is safe without the lock.
      update_state(event.state_delta) if event.state_delta && !event.state_delta.empty?

      Legate.logger.debug("Session #{@id}: Event added - Role: #{event.role}, Tool: #{event.tool_name || 'N/A'}")
      event
    end

    # --- State Management Methods ---

    # Gets a value from the session state.
    # @param key [Symbol, String] The key to retrieve.
    # @return [Object, nil] The value associated with the key, or nil if not found.
    def get_state(key)
      prefix, real_key = parse_key(key)
      validate_prefix!(prefix) if prefix # match set/update/delete: reads and writes agree on what a key means
      if prefix
        @session_service&.load_scoped_state(scoped_namespace(prefix), real_key)
      else
        @state[real_key.to_sym]
      end
    end

    # Sets a value in the session state.
    # @param key [Symbol, String] The key to set.
    # @param value [Object] The value to store.
    # @raise [Legate::StateValidationError] If the value cannot be serialized
    # @raise [Legate::InvalidPrefixError] If an invalid prefix is used
    # @return [Object] The value that was set.
    def set_state(key, value)
      validate_serializable!(value)
      prefix, real_key = parse_key(key)
      validate_prefix!(prefix) if prefix

      touch!
      if prefix
        @session_service&.save_scoped_state(scoped_namespace(prefix), real_key, value)
      else
        @state[real_key.to_sym] = value
      end
      value
    end

    # Merges a hash into the session state.
    # @param hash [Hash] The hash to merge into the state.
    # @raise [Legate::StateValidationError] If any value cannot be serialized
    # @raise [Legate::InvalidPrefixError] If any key has an invalid prefix
    def update_state(hash)
      return unless hash.is_a?(Hash)

      touch!
      hash.each do |k, v|
        validate_serializable!(v)
        prefix, real_key = parse_key(k)
        validate_prefix!(prefix) if prefix

        if prefix
          @session_service&.save_scoped_state(scoped_namespace(prefix), real_key, v)
        else
          @state[real_key.to_sym] = v
        end
      end
    end

    # Deletes a key from the session state.
    # @param key [Symbol, String] The key to delete.
    # @return [Object, nil] The value of the deleted key, or nil if not found.
    def delete_state(key)
      prefix, real_key = parse_key(key)
      validate_prefix!(prefix) if prefix

      touch!
      if prefix
        @session_service&.clear_scoped_state(scoped_namespace(prefix), real_key)
      else
        @state.delete(real_key.to_sym)
      end
    end

    # Clears all key-value pairs from the session state.
    def clear_state!
      touch!
      @state.clear
      VALID_PREFIXES.each do |prefix|
        @session_service&.clear_scoped_state(scoped_namespace(prefix), '*')
      end
    end

    # Provides a plain Hash representation of the current state.
    # @return [Hash] A copy of the session state.
    def state_to_h
      # Convert Concurrent::Map to a regular Hash
      Hash[@state.to_enum(:each_pair).to_a]
    end

    # --- Serialization Helpers ---

    # Serializes the entire session object to a Hash suitable for JSON conversion.
    # @return [Hash] Hash representation of the session.
    def to_h
      serialized_events = @mutex.synchronize { @events.map(&:to_h) }
      {
        id: @id,
        app_name: @app_name,
        user_id: @user_id,
        created_at: @created_at.iso8601(3),
        updated_at: @updated_at.iso8601(3),
        state: state_to_h,
        events: serialized_events
      }
    end

    # Deserializes session data from a hash into a Session object.
    # @param hash [Hash] Hash containing session data (typically from JSON).
    # @return [Legate::Session] A new Session object.
    def self.from_h(hash)
      sym_hash = hash.transform_keys(&:to_sym) # Ensure keys are symbols
      events_data = sym_hash[:events] || []
      events = events_data.map { |event_hash| Legate::Event.from_h(event_hash.transform_keys(&:to_sym)) }.compact

      new(
        id: sym_hash[:id],
        app_name: sym_hash[:app_name],
        user_id: sym_hash[:user_id],
        initial_state: sym_hash[:state] || {},
        events: events
      ).tap do |session|
        # Set timestamps after initialization
        session.instance_variable_set(:@created_at, Time.iso8601(sym_hash[:created_at])) if sym_hash[:created_at]
        session.instance_variable_set(:@updated_at, Time.iso8601(sym_hash[:updated_at])) if sym_hash[:updated_at]
      end
    rescue ArgumentError, TypeError => e
      Legate.logger.error("Session.from_h: Failed to deserialize session data. Error: #{e.message}. Data: #{hash.inspect}")
      nil # Return nil on deserialization error
    end

    private

    # Records a state mutation by bumping @updated_at under the mutex, so the
    # timestamp write doesn't race add_event's. The external scoped-state I/O is
    # intentionally left outside the lock (see add_event).
    def touch!
      @mutex.synchronize { @updated_at = Time.now.utc }
    end

    def parse_key(key)
      key_str = key.to_s
      if key_str.include?(':')
        prefix, real_key = key_str.split(':', 2)
        [prefix, real_key]
      else
        [nil, key_str]
      end
    end

    # Builds the identity-qualified namespace passed to the session service for a
    # scoped-state prefix, so scoped state is isolated by owner instead of sharing
    # one global slot per prefix:
    #   user → per (app, user), shared across that user's sessions
    #   app  → per app, shared across the app's users
    #   temp → per session
    # The session service treats this whole string as an opaque scope, so wildcard
    # clears (clear_scoped_state(ns, '*')) only touch the caller's own subtree.
    # @param prefix [String] One of VALID_PREFIXES.
    # @return [String] The namespace string.
    def scoped_namespace(prefix)
      case prefix
      when 'user' then "user:#{escape_ns(@app_name)}:#{escape_ns(@user_id)}"
      when 'app'  then "app:#{escape_ns(@app_name)}"
      when 'temp' then "temp:#{escape_ns(@id)}"
      else prefix
      end
    end

    # Escapes ':' in identity components so a crafted app_name/user_id/id cannot
    # traverse into another owner's namespace.
    def escape_ns(component)
      component.to_s.gsub(':', '%3A')
    end

    def validate_prefix!(prefix)
      return if prefix.nil?
      return if VALID_PREFIXES.include?(prefix)

      raise Legate::InvalidPrefixError, "Invalid state key prefix: #{prefix}. Valid prefixes: #{VALID_PREFIXES.join(', ')}"
    end

    # Recursively checks if a value is JSON-serializable (basic types, nil, nested Hashes/Arrays thereof)
    def is_json_serializable?(value)
      case value
      when String, Integer, TrueClass, FalseClass, NilClass
        true
      when Float
        value.finite? # NaN/Infinity are Floats but JSON.generate raises on them — reject up front
      when Hash
        # Ensure all keys are strings/symbols and all values are serializable
        value.all? { |k, v| (k.is_a?(String) || k.is_a?(Symbol)) && is_json_serializable?(v) }
      when Array
        value.all? { |v| is_json_serializable?(v) }
      else
        false # Other types (Time, Set, Object, etc.) are not serializable
      end
    end

    # Raises error if value is not serializable
    def validate_serializable!(value)
      return if is_json_serializable?(value)

      raise Legate::SerializationError,
            "Value must be JSON-serializable (basic types, nil, Hash, Array): #{value.inspect}"
    end
  end # End Session class
end # End Legate module
