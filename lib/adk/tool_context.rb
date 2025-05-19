# File: lib/adk/tool_context.rb
# frozen_string_literal: true

module ADK
  # Provides contextual information to ADK::Tool#perform_execution
  # Includes session details and a reference to the agent's tool registry.
  # Read-only.
  class ToolContext
    attr_reader :session_id, :user_id, :app_name, :tool_registry, :session_service, :logger, :invocation_id

    # Expose pending state delta for inspection but not direct modification
    attr_reader :pending_state_delta

    # @param session_id [String] The ID of the current session.
    # @param user_id [String] The user ID associated with the session.
    # @param app_name [String] The application/agent name associated with the session.
    # @param tool_registry [ADK::ToolRegistry] The tool registry instance of the agent executing the tool.
    # @param session_service [ADK::SessionService::Base, nil] The session service instance.
    # @param logger [Logger, nil] The logger instance.
    # @param invocation_id [String, nil] The ID of the current agent invocation.
    def initialize(session_id:, user_id:, app_name:, tool_registry: nil, session_service: nil, logger: ADK.logger, invocation_id: nil)
      @session_id = session_id
      @user_id = user_id
      @app_name = app_name
      @tool_registry = tool_registry
      @session_service = session_service
      @invocation_id = invocation_id
      @pending_state_delta = {}
    end

    # Retrieves a value from the session state via the session_service.
    # @param key [Symbol, String] The key to retrieve
    # @return [Object, nil] The value or nil if not found
    def state_get(key)
      unless @session_service
        ADK.logger.warn { "[ToolContext] state_get called but no session_service available." }
        return nil
      end

      ADK.logger.debug { "[ToolContext] state_get for key: #{key} in session: #{@session_id}" }
      @session_service.get_state(session_id: @session_id, key: key)
    rescue => e
      ADK.logger.error { "[ToolContext] Error in state_get for key '#{key}': #{e.message}" }
      nil
    end

    # Sets a value in the pending state delta for this context.
    # @param key [Symbol, String] The key to set
    # @param value [Object] The value to store (should be serializable)
    def state_set(key, value)
      ADK.logger.debug { "[ToolContext] state_set for key: #{key} to value: #{value.inspect} (pending)" }
      @pending_state_delta[key.to_sym] = value
    end

    # Merges a hash into the pending state delta for this context.
    # @param hash_to_merge [Hash] The hash to merge into the pending state delta
    def state_update(hash_to_merge)
      unless hash_to_merge.is_a?(Hash)
        ADK.logger.warn { "[ToolContext] state_update called with non-hash: #{hash_to_merge.class}" }
        return
      end

      ADK.logger.debug { "[ToolContext] state_update with hash: #{hash_to_merge.inspect} (pending)" }
      @pending_state_delta.merge!(hash_to_merge.transform_keys(&:to_sym))
    end

    # Clears any accumulated pending state changes within this context instance.
    def clear_pending_state_delta!
      @pending_state_delta = {}
    end

    def to_h
      {
        session_id: @session_id,
        user_id: @user_id,
        app_name: @app_name,
        invocation_id: @invocation_id,
        tool_registry_object_id: @tool_registry&.object_id,
        session_service_present: !@session_service.nil?
      }
    end
  end
end
