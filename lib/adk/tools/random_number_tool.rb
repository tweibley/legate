# File: lib/adk/tools/random_number_tool.rb
# frozen_string_literal: true

require_relative '../tool'

module ADK
  module Tools
    class RandomNumberTool < ADK::Tool
      define_metadata(
        name: :random_number,
        description: 'Generates a random integer between a minimum and maximum value (inclusive). Defaults to 1-100.',
        parameters: {
          min: {
            type: :integer,
            description: 'The minimum value for the random number (inclusive).',
            required: false
          },
          max: {
            type: :integer,
            description: 'The maximum value for the random number (inclusive).',
            required: false
          }
        }
      )

      def initialize(**options)
        super(**options)
      end

      private

      # @param params [Hash] Contains min and max.
      # @param _context [ADK::ToolContext, nil] The execution context (unused here).
      def perform_execution(params, _context)
        begin
          # Fetch parameters safely, providing defaults
          min_val_str = params.fetch('min') { params.fetch(:min, '1') }
          max_val_str = params.fetch('max') { params.fetch(:max, '100') }

          begin
            min_val = Integer(min_val_str)
            max_val = Integer(max_val_str)
          rescue ArgumentError, TypeError
            err_msg = "Invalid integer input provided for min or max. Min: '#{min_val_str}', Max: '#{max_val_str}'"
            ADK.logger.error("RandomNumberTool Argument Error: #{err_msg}")
            raise ADK::ToolArgumentError, err_msg
          end

          # Check logical constraint
          if min_val > max_val
            err_msg = "Min value (#{min_val}) cannot be greater than Max value (#{max_val})."
            ADK.logger.error("RandomNumberTool Argument Error: #{err_msg}")
            raise ADK::ToolArgumentError, err_msg
          end

          # Perform the core logic
          random_num = rand(min_val..max_val)
          ADK.logger.info("RandomNumberTool generated: #{random_num} (Range: #{min_val}-#{max_val})")
          { status: :success, result: random_num }
        rescue ADK::ToolArgumentError => e # Re-raise specific argument errors
          raise e
        rescue StandardError => e # Catch unexpected errors during the process
          ADK.logger.error("RandomNumberTool: Unexpected error: #{e.class} - #{e.message}")
          # Wrap unexpected errors in a ToolError
          raise ADK::ToolError, "Unexpected error in RandomNumber tool: #{e.message}"
        end
      end
    end # End RandomNumberTool class
  end # End Tools module
end # End ADK module
