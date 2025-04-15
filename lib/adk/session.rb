# frozen_string_literal: true

require 'concurrent'
require 'securerandom'

module ADK
  # Session class represents a session for an agent
  class Session
    attr_reader :agent, :id, :created_at, :updated_at

    # Initialize a new session
    # @param agent [Agent] The agent this session belongs to
    # @param options [Hash] Additional options for the session
    def initialize(agent:, **options)
      @agent = agent
      @id = options[:id] || SecureRandom.uuid
      @created_at = Time.now
      @updated_at = @created_at
      @state = Concurrent::Map.new
    end

    # Get a value from the session state
    # @param key [Symbol] The key to get
    # @return [Object] The value
    def get(key)
      @state[key]
    end

    # Set a value in the session state
    # @param key [Symbol] The key to set
    # @param value [Object] The value to set
    # @return [Object] The value
    def set(key, value)
      @updated_at = Time.now
      @state[key] = value
    end

    # Delete a value from the session state
    # @param key [Symbol] The key to delete
    # @return [Object] The deleted value
    def delete(key)
      @updated_at = Time.now
      @state.delete(key)
    end

    # Clear the session state
    # @return [self]
    def clear
      @updated_at = Time.now
      @state.clear
      self
    end

    # Get all session state
    # @return [Hash] The session state
    def state
      @state.to_h
    end

    # Check if the session has a key
    # @param key [Symbol] The key to check
    # @return [Boolean] Whether the session has the key
    def key?(key)
      @state.key?(key)
    end
  end
end 