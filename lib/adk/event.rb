# File: lib/adk/event.rb
# frozen_string_literal: true

require 'time'
require 'json' # Needed for serialization examples/potential
require 'securerandom' # Required for SecureRandom

module ADK
  # Represents a single interaction or step within a Session's history.
  # Immutable object after creation.
  #
  # @!attribute [r] role
  #   @return [Symbol] The origin of the event (:user, :agent, :tool_request, :tool_result).
  # @!attribute [r] content
  #   @return [String, Hash] The payload of the event (e.g., user text, agent text, tool params, tool result hash).
  # @!attribute [r] timestamp
  #   @return [Time] The UTC time the event occurred.
  # @!attribute [r] tool_name
  #   @return [Symbol, nil] The name of the tool involved (for :tool_request, :tool_result roles).
  # @!attribute [r] state_delta
  #   @return [Hash, nil] Optional hash representing state changes associated with this event. Keys should be symbols.
  # @!attribute [r] event_id
  #   @return [String] A unique ID for this specific event instance.
  Event = Struct.new(:role, :content, :timestamp, :tool_name, :state_delta, :event_id, keyword_init: true) do
    # @param role [Symbol] :user, :agent, :tool_request, :tool_result
    # @param content [String, Hash] Event payload. Should be JSON-serializable.
    # @param timestamp [Time, nil] Timestamp (defaults to Time.now.utc).
    # @param tool_name [Symbol, nil] Name of the tool if role is tool related.
    # @param state_delta [Hash, nil] State changes to apply with this event.
    # @param event_id [String, nil] Unique event ID (defaults to SecureRandom.uuid).
    def initialize(role:, content:, timestamp: nil, tool_name: nil, state_delta: nil, event_id: nil)
      # Basic validation
      unless [:user, :agent, :tool_request, :tool_result].include?(role)
        raise ArgumentError, "Invalid role: #{role}. Must be :user, :agent, :tool_request, or :tool_result."
      end

      if [:tool_request, :tool_result].include?(role) && (tool_name.nil? || !tool_name.is_a?(Symbol))
        ADK.logger.warn("Event: :#{role} event created without a valid :tool_name symbol.")
      end

      # Validate state_delta is a Hash or nil
      unless state_delta.nil? || state_delta.is_a?(Hash)
        ADK.logger.warn("Event: :state_delta must be a Hash or nil, received #{state_delta.class}.")
        state_delta = nil # Force to nil if invalid
      end

      # Ensure content is somewhat reasonable (avoids deep inspection for performance)
      unless content.is_a?(String) || content.is_a?(Hash) || content.is_a?(Array) || content.is_a?(NilClass) || content.is_a?(Numeric) || content.is_a?(TrueClass) || content.is_a?(FalseClass)
        ADK.logger.warn("Event: Content is of unusual type (#{content.class}): #{content.inspect}")
      end

      super(
        role: role,
        content: content,
        timestamp: timestamp || Time.now.utc,
        tool_name: tool_name,
        state_delta: state_delta&.transform_keys(&:to_sym), # Ensure keys are symbols
        event_id: event_id || SecureRandom.uuid
      )
      # Freeze the object to make it immutable after creation
      freeze
    end

    # Helper to check if the event represents a final agent response to the user.
    # @return [Boolean]
    def final_agent_response?
      role == :agent
    end

    # Basic serialization for storage (e.g., in Redis).
    # @return [Hash] A hash representation suitable for JSON conversion.
    def to_h
      {
        role: role,
        content: content, # Assumes content is already JSON-serializable
        timestamp: timestamp.iso8601(3), # Use ISO8601 format with milliseconds
        tool_name: tool_name,
        state_delta: state_delta, # Store the hash directly (must be JSON-serializable)
        event_id: event_id
      }
    end

    # Basic deserialization from a hash (e.g., after reading from JSON).
    # @param hash [Hash] The hash containing event data (uses symbolized keys).
    # @return [ADK::Event] A new Event object.
    def self.from_h(hash)
      # Ensure keys are symbolized for consistent access
      sym_hash = hash.transform_keys(&:to_sym)

      new(
        role: sym_hash[:role]&.to_sym, # Safely convert role to symbol
        content: sym_hash[:content],
        # Safely parse timestamp
        timestamp: sym_hash[:timestamp] ? Time.iso8601(sym_hash[:timestamp]) : Time.now.utc,
        tool_name: sym_hash[:tool_name]&.to_sym, # Safely convert tool_name to symbol
        # Deserialize state_delta, ensuring keys are symbols
        state_delta: sym_hash[:state_delta]&.transform_keys(&:to_sym),
        event_id: sym_hash[:event_id]
      )
    rescue ArgumentError => e
      ADK.logger.error("Event.from_h: Failed to parse timestamp or invalid role: #{e.message}. Hash: #{hash.inspect}")
      # Decide on fallback: return nil, raise, or return partial object?
      # Returning nil might be safest to signal deserialization failure.
      nil
    rescue TypeError => e
      ADK.logger.error("Event.from_h: Type error during deserialization (check state_delta?): #{e.message}. Hash: #{hash.inspect}")
      nil
    end
  end
end