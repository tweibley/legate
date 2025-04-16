# File: lib/adk/session.rb
# frozen_string_literal: true

require 'concurrent'
require 'securerandom'
require 'json'
require_relative 'event' # Require the new Event class

module ADK
  # Represents a single, ongoing conversation thread between a user and an agent system.
  # It holds the history of interactions (Events) and temporary session-specific data (State).
  class Session
    attr_reader :id, :app_name, :user_id, :created_at, :events
    attr_accessor :updated_at # Allow service to update this

    # Initializes a new session. Typically called by a SessionService.
    # @param id [String] A unique identifier for the session (defaults to UUID).
    # @param app_name [String] Identifier for the agent application.
    # @param user_id [String] Identifier for the user initiating the session.
    # @param initial_state [Hash] Optional initial data for the session state. Keys are symbolized.
    # @param events [Array<ADK::Event>] Optional initial list of events (for reloading).
    def initialize(id: nil, app_name:, user_id:, initial_state: {}, events: [])
      @id = id || SecureRandom.uuid
      @app_name = app_name
      @user_id = user_id
      @created_at = Time.now.utc # Use UTC
      @updated_at = @created_at
      # Use Concurrent::Map for thread-safe state storage within the session object itself
      @state = Concurrent::Map.new(initial_state.transform_keys(&:to_sym))
      # Events array stores the history, ensure it's mutable if passed and validate contents
      @events = events.map do |e|
        e.is_a?(ADK::Event) ? e : (ADK.logger.warn("Session Init: Invalid event data skipped: #{e.inspect}"); nil)
      end.compact
      ADK.logger.debug("Session initialized: id=#{@id}, app=#{@app_name}, user=#{@user_id}, event_count=#{@events.size}")
    end

    # Provides access to the session's temporary state data.
    # @return [Concurrent::Map] The thread-safe state map.
    def state
      @state
    end

    # Adds an event to the session's history. Typically called by the SessionService.
    # This method itself doesn't persist the change; SessionService#save_session does.
    # @param event [ADK::Event] The event object to add.
    # @return [ADK::Event, nil] The added event or nil if the input was invalid.
    def add_event(event)
      unless event.is_a?(ADK::Event)
        ADK.logger.error("Session #{@id}: Attempted to add invalid event: #{event.inspect}")
        return nil
      end
      @events << event
      @updated_at = Time.now.utc # Update timestamp when history changes
      ADK.logger.debug("Session #{@id}: Event added (in memory) - Role: #{event.role}, Tool: #{event.tool_name || 'N/A'}")
      event
    end

    # --- State Management Methods ---

    # Gets a value from the session state.
    # @param key [Symbol, String] The key to retrieve.
    # @return [Object, nil] The value associated with the key, or nil if not found.
    def get_state(key)
      @state[key.to_sym]
    end

    # Sets a value in the session state. Keys are stored as symbols.
    # Does not persist; SessionService#save_session or add_event_and_update_state should be used.
    # @param key [Symbol, String] The key to set.
    # @param value [Object] The value to store.
    # @return [Object] The value that was set.
    def set_state(key, value)
      @updated_at = Time.now.utc
      @state[key.to_sym] = value
    end

    # Merges a hash into the session state. Existing keys are overwritten.
    # Does not persist; SessionService#save_session or add_event_and_update_state should be used.
    # @param hash [Hash] The hash to merge into the state. Keys will be symbolized.
    def update_state(hash)
      return unless hash.is_a?(Hash)

      @updated_at = Time.now.utc
      hash.each { |k, v| @state[k.to_sym] = v }
    end

    # Deletes a key from the session state.
    # Does not persist; SessionService#save_session should be used.
    # @param key [Symbol, String] The key to delete.
    # @return [Object, nil] The value of the deleted key, or nil if not found.
    def delete_state(key)
      @updated_at = Time.now.utc
      @state.delete(key.to_sym)
    end

    # Clears all key-value pairs from the session state.
    # Does not persist; SessionService#save_session should be used.
    def clear_state!
      @updated_at = Time.now.utc
      @state.clear
    end

    # Provides a plain Hash representation of the current state.
    # @return [Hash] A copy of the session state.
    def state_to_h
      @state.to_h
    end

    # --- Serialization Helpers ---

    # Serializes the entire session object to a Hash suitable for JSON conversion.
    # @return [Hash] Hash representation of the session.
    def to_h
      {
        id: @id,
        app_name: @app_name,
        user_id: @user_id,
        created_at: @created_at.iso8601(3),
        updated_at: @updated_at.iso8601(3),
        state: state_to_h, # Convert Concurrent::Map to Hash
        events: @events.map(&:to_h) # Serialize each event
      }
    end

    # Deserializes session data from a hash into a Session object.
    # @param hash [Hash] Hash containing session data (typically from JSON).
    # @return [ADK::Session] A new Session object.
    def self.from_h(hash)
      sym_hash = hash.transform_keys(&:to_sym) # Ensure keys are symbols
      events_data = sym_hash[:events] || []
      events = events_data.map { |event_hash| ADK::Event.from_h(event_hash.transform_keys(&:to_sym)) }.compact

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
      ADK.logger.error("Session.from_h: Failed to deserialize session data. Error: #{e.message}. Data: #{hash.inspect}")
      nil # Return nil on deserialization error
    end
  end # End Session class
end # End ADK module
