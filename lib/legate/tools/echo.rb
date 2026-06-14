# File: lib/legate/tools/echo.rb
# frozen_string_literal: true

require_relative '../tool'

module Legate
  module Tools
    class Echo < Tool
      # --- New DSL Metadata ---
      # Name :echo will be inferred
      tool_description 'Echoes back the provided message.'

      parameter :message,
                type: :string,
                description: 'The message to echo',
                required: true
      # --- End New DSL Metadata ---

      private

      # @param params [Hash] Contains :message.
      # @param _context [Legate::ToolContext, nil] The execution context (unused here).
      def perform_execution(params, _context)
        # Fetch validated parameter
        message = params.fetch('message') { params.fetch(:message, nil) }

        # This check is belts-and-suspenders; validation should catch missing required params.
        unless message
          err_msg = 'Internal Error: Message parameter missing in perform_execution for Echo tool after validation.'
          Legate.logger.error(err_msg)
          raise Legate::ToolError, err_msg
        end

        # Simple success case
        { status: :success, result: message }
      rescue StandardError => e # Catch any truly unexpected errors during fetch/processing
        Legate.logger.error("Echo Tool: Unexpected error: #{e.class} - #{e.message}")
        # Wrap unexpected errors in a ToolError
        raise Legate::ToolError, "Unexpected error in Echo tool: #{e.message}"
      end
    end # End Echo class
  end # End Tools module
end # End Legate module
