# File: lib/adk/tool_context.rb
# frozen_string_literal: true

module ADK
  # Provides contextual information to ADK::Tool#perform_execution
  # Currently includes session details. Read-only.
  class ToolContext
    attr_reader :session_id, :user_id, :app_name

    # @param session_id [String] The ID of the current session.
    # @param user_id [String] The user ID associated with the session.
    # @param app_name [String] The application/agent name associated with the session.
    def initialize(session_id:, user_id:, app_name:)
      @session_id = session_id
      @user_id = user_id
      @app_name = app_name
      freeze # Make context immutable
    end

    def to_h
      {
        session_id: @session_id,
        user_id: @user_id,
        app_name: @app_name
      }
    end
  end
end
