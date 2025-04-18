# File: lib/adk/tools/calculator.rb
# frozen_string_literal: true

# Removed require 'logger' - Use ADK.logger
require_relative '../tool' # Ensure base class is loaded

module ADK
  module Tools
    # A simple calculator tool supporting basic arithmetic operations.
    class Calculator < Tool
      # --- Define Metadata (This triggers registration) ---
      define_metadata(
        name: :calculator,
        description: 'Calculates the result of an arithmetic operation. Requires two numbers (operand1, operand2) and the operation name (operation: "add", "subtract", "multiply", "divide", or symbols +, -, *, /).',
        parameters: {
          operand1: {
            type: :numeric,
            description: 'The first number for the calculation.',
            required: true
          },
          operand2: {
            type: :numeric,
            description: 'The second number for the calculation.',
            required: true
          },
          operation: {
            type: :string,
            description: 'The operation to perform (e.g., "add", "subtract", "multiply", "divide", "+", "-", "*", "/").',
            required: true
          }
        }
      )
      # --- End Metadata ---

      # REMOVED: LOGGER = Logger.new($stdout)

      def initialize(**options)
        super(**options)
        # No specific initialization needed for this tool
      end

      private

      # @param params [Hash] Contains operand1, operand2, operation.
      # @param _context [ADK::ToolContext, nil] The execution context (unused here).
      def perform_execution(params, _context)
        op1_str = params.fetch('operand1') { params.fetch(:operand1, nil) }
        op2_str = params.fetch('operand2') { params.fetch(:operand2, nil) }
        operation = params.fetch('operation') { params.fetch(:operation, nil) }&.downcase

        begin
          op1 = Float(op1_str)
          op2 = Float(op2_str)
        rescue ArgumentError, TypeError
          err_msg = "Invalid numeric input provided for operands. Op1: '#{op1_str}', Op2: '#{op2_str}'"
          ADK.logger.error("Calculator Tool Error: #{err_msg}")
          # --- Return Error Hash ---
          return { status: :error, error_message: err_msg }
        end

        result_val = case operation
                     when 'add', '+' then op1 + op2
                     when 'subtract', '-' then op1 - op2
                     when 'multiply', '*' then op1 * op2
                     when 'divide', '/'
                       if op2.zero?
                         err_msg = "Division by zero is not allowed."
                         ADK.logger.error("Calculator Tool Error: #{err_msg}")
                         # --- Return Error Hash ---
                         return { status: :error, error_message: err_msg }
                       else
                         op1 / op2
                       end
                     else
                       err_msg = "Unsupported operation: '#{operation}'. Use add, subtract, multiply, or divide (or +, -, *, /)."
                       ADK.logger.warn("Calculator Tool Warning: #{err_msg}")
                       # --- Return Error Hash ---
                       return { status: :error, error_message: err_msg }
                     end

        ADK.logger.info("Calculator Tool: #{op1} #{operation} #{op2} = #{result_val}")
        # --- Return Success Hash ---
        { status: :success, result: result_val }

      # Catch potential unexpected errors during execution logic itself
      rescue ADK::Error => e # Catch specific ADK errors if needed
        ADK.logger.error("Calculator Tool ADK::Error: #{e.message}")
        return { status: :error, error_message: e.message }
      rescue StandardError => e
        ADK.logger.error("Calculator Tool: Unexpected error during calculation: #{e.class} - #{e.message}")
        # Consider logging backtrace here for unexpected errors
        return { status: :error, error_message: "Calculation failed due to an unexpected internal error: #{e.message}" }
      end
    end # End Calculator class
  end # End Tools module
end # End ADK module
