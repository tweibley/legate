# File: lib/adk/tools/calculator.rb
# frozen_string_literal: true

# Removed require 'logger' - Use ADK.logger
require_relative '../tool' # Ensure base class is loaded

module ADK
  module Tools
    # A simple calculator tool supporting basic arithmetic operations.
    class Calculator < Tool
      # --- New DSL Metadata ---
      # Name :calculator will be inferred
      tool_description 'Calculates the result of an arithmetic operation. Requires two numbers (operand1, operand2) and the operation name (operation: "add", "subtract", "multiply", "divide", or symbols +, -, *, /).'

      parameter :operand1,
                type: :numeric,
                description: 'The first number for the calculation.',
                required: true

      parameter :operand2,
                type: :numeric,
                description: 'The second number for the calculation.',
                required: true

      parameter :operation,
                type: :string,
                description: 'The operation to perform (e.g., "add", "subtract", "multiply", "divide", "+", "-", "*", "/").',
                required: true
      # --- End New DSL Metadata ---

      # REMOVED: Old define_metadata block

      # REMOVED: explicit initialize is no longer needed as superclass handles it.
      # def initialize(**options)
      #   super(**options)
      #   # No specific initialization needed for this tool
      # end

      private

      # @param params [Hash] Contains operand1, operand2, operation.
      # @param _context [ADK::ToolContext, nil] The execution context (unused here).
      def perform_execution(params, _context)
        op1_str = params.fetch('operand1') { params.fetch(:operand1, nil) }
        op2_str = params.fetch('operand2') { params.fetch(:operand2, nil) }
        operation = params.fetch('operation') { params.fetch(:operation, nil) }&.downcase

        begin
          # Validate inputs first
          begin
            op1 = Float(op1_str)
            op2 = Float(op2_str)
          rescue ArgumentError, TypeError
            err_msg = "Invalid numeric input provided for operands. Op1: '#{op1_str}', Op2: '#{op2_str}'"
            ADK.logger.error("Calculator Tool Argument Error: #{err_msg}")
            raise ADK::ToolArgumentError, err_msg
          end

          valid_ops = %w[add subtract multiply divide + - * /]
          unless valid_ops.include?(operation)
            err_msg = "Unsupported operation: '#{operation}'. Use add, subtract, multiply, or divide (or +, -, *, /)."
            ADK.logger.warn("Calculator Tool Argument Warning: #{err_msg}")
            raise ADK::ToolArgumentError, err_msg
          end

          if (%w[divide /].include?(operation)) && op2.zero?
            err_msg = "Division by zero is not allowed."
            ADK.logger.error("Calculator Tool Argument Error: #{err_msg}")
            raise ADK::ToolArgumentError, err_msg
          end

          # Perform calculation
          result_val = case operation
                       when 'add', '+' then op1 + op2
                       when 'subtract', '-' then op1 - op2
                       when 'multiply', '*' then op1 * op2
                       when 'divide', '/' then op1 / op2 # Zero already checked
                         # No else needed due to validation above
                       end

          ADK.logger.info("Calculator Tool: #{op1} #{operation} #{op2} = #{result_val}")
          { status: :success, result: result_val }

        # Catch potential unexpected errors during execution logic itself
        rescue ADK::ToolArgumentError => e # Re-raise argument errors
          raise e
        rescue ADK::ToolError => e # Catch specific ADK tool errors if they occur somehow
          ADK.logger.error("Calculator Tool ADK::ToolError: #{e.message}")
          raise e # Re-raise to be handled by the agent
        rescue StandardError => e
          # Wrap unexpected errors in a ToolError
          ADK.logger.error("Calculator Tool: Unexpected internal error during calculation: #{e.class} - #{e.message}")
          raise ADK::ToolError, "Calculation failed due to an unexpected internal error: #{e.message}"
        end
      end # End perform_execution
    end # End Calculator class
  end # End Tools module
end # End ADK module
