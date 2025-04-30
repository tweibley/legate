# File: lib/adk/tools/echo.rb
# frozen_string_literal: true

require_relative '../tool'

module ADK
  module Tools
    class Echo < Tool
      define_metadata(
        name: :echo,
        description: 'Echoes back the provided message.',
        parameters: {
          message: {
            type: :string,
            description: 'The message to echo',
            required: true
          }
        }
      )

      def initialize(**options)
        super(**options)
      end

      private

      # @param params [Hash] Contains :message.
      # @param _context [ADK::ToolContext, nil] The execution context (unused here).
      def perform_execution(params, _context)
        begin
          # Fetch validated parameter
          message = params.fetch('message') { params.fetch(:message, nil) }

          # This check is belts-and-suspenders; validation should catch missing required params.
          unless message
            err_msg = "Internal Error: Message parameter missing in perform_execution for Echo tool after validation."
            ADK.logger.error(err_msg)
            raise ADK::ToolError, err_msg
          end

          # Simple success case
          { status: :success, result: message }
        rescue StandardError => e # Catch any truly unexpected errors during fetch/processing
          ADK.logger.error("Echo Tool: Unexpected error: #{e.class} - #{e.message}")
          # Wrap unexpected errors in a ToolError
          raise ADK::ToolError, "Unexpected error in Echo tool: #{e.message}"
        end
      end
    end # End Echo class
  end # End Tools module
end # End ADK module
