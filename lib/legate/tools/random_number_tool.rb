# File: lib/legate/tools/random_number_tool.rb
# frozen_string_literal: true

require_relative '../tool'

module Legate
  module Tools
    class RandomNumberTool < Legate::Tool
      # --- New DSL Metadata ---
      # Name will be inferred as :random_number_tool
      self.explicit_tool_name = :random_number # Keep original name

      tool_description 'Generates a random integer between a minimum and maximum value (inclusive). Defaults to 1-100.'

      parameter :min,
                type: :integer,
                description: 'The minimum value for the random number (inclusive).',
                required: false

      parameter :max,
                type: :integer,
                description: 'The maximum value for the random number (inclusive).',
                required: false
      # --- End New DSL Metadata ---

      private

      # @param params [Hash] Contains min and max.
      # @param _context [Legate::ToolContext, nil] The execution context (unused here).
      def perform_execution(params, _context)
        # Fetch parameters safely, providing defaults
        min_val_str = params.fetch('min') { params.fetch(:min, '1') }
        max_val_str = params.fetch('max') { params.fetch(:max, '100') }

        begin
          min_val = Integer(min_val_str)
          max_val = Integer(max_val_str)
        rescue ArgumentError, TypeError
          err_msg = "Invalid integer input provided for min or max. Min: '#{min_val_str}', Max: '#{max_val_str}'"
          Legate.logger.error("RandomNumberTool Argument Error: #{err_msg}")
          raise Legate::ToolArgumentError, err_msg
        end

        # Check logical constraint
        if min_val > max_val
          err_msg = "Min value (#{min_val}) cannot be greater than Max value (#{max_val})."
          Legate.logger.error("RandomNumberTool Argument Error: #{err_msg}")
          raise Legate::ToolArgumentError, err_msg
        end

        # Perform the core logic
        random_num = rand(min_val..max_val)
        Legate.logger.info("RandomNumberTool generated: #{random_num} (Range: #{min_val}-#{max_val})")
        { status: :success, result: random_num }
      rescue Legate::ToolArgumentError => e # Re-raise specific argument errors
        raise e
      rescue StandardError => e # Catch unexpected errors during the process
        Legate.logger.error("RandomNumberTool: Unexpected error: #{e.class} - #{e.message}")
        # Wrap unexpected errors in a ToolError
        raise Legate::ToolError, "Unexpected error in RandomNumber tool: #{e.message}"
      end
    end # End RandomNumberTool class
  end # End Tools module
end # End Legate module
