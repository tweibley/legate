# File: lib/adk/tool_context.rb
# frozen_string_literal: true

module ADK
  # Provides contextual information to ADK::Tool#perform_execution
  # Includes session details and a reference to the agent's tool registry.
  # Read-only.
  class ToolContext
    attr_reader :session_id, :user_id, :app_name, :tool_registry

    # @param session_id [String] The ID of the current session.
    # @param user_id [String] The user ID associated with the session.
    # @param app_name [String] The application/agent name associated with the session.
    # @param tool_registry [ADK::ToolRegistry] The tool registry instance of the agent executing the tool.
    def initialize(session_id:, user_id:, app_name:, tool_registry: nil)
      @session_id = session_id
      @user_id = user_id
      @app_name = app_name
      @tool_registry = tool_registry
      freeze # Make context immutable
    end

    def to_h
      {
        session_id: @session_id,
        user_id: @user_id,
        app_name: @app_name,
        tool_registry_object_id: @tool_registry&.object_id
      }
    end
  end
end
