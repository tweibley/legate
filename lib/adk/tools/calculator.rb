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
        description: 'Performs basic arithmetic operations (add, subtract, multiply, divide).',
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

      # Performs the calculation based on validated parameters.
      def perform_execution(params)
        op1_str = params.fetch('operand1') { params.fetch(:operand1, nil) }
        op2_str = params.fetch('operand2') { params.fetch(:operand2, nil) }
        operation = params.fetch('operation') { params.fetch(:operation, nil) }&.downcase

        begin
          op1 = Float(op1_str)
          op2 = Float(op2_str)
        rescue ArgumentError, TypeError
          # Use central logger
          ADK.logger.error("Calculator Tool: Invalid numeric input received. Operand1: '#{op1_str}', Operand2: '#{op2_str}'")
          raise ADK::Error, "Invalid numeric input provided for operands."
        end

        result = case operation
                 when 'add', '+' then op1 + op2
                 when 'subtract', '-' then op1 - op2
                 when 'multiply', '*' then op1 * op2
                 when 'divide', '/'
                   if op2.zero?
                     # No specific logging needed here, the error message is clear
                     raise ADK::Error, "Division by zero is not allowed."
                   else
                     op1 / op2
                   end
                 else
                   # Use central logger
                   ADK.logger.warn("Calculator Tool: Unsupported operation '#{operation}' requested.")
                   raise ADK::Error,
                         "Unsupported operation: '#{operation}'. Use add, subtract, multiply, or divide (or +, -, *, /)."
                 end

        # Use central logger
        ADK.logger.info("Calculator Tool: #{op1} #{operation} #{op2} = #{result}")
        result
      rescue StandardError => e
        # Use central logger
        ADK.logger.error("Calculator Tool: Unexpected error during calculation: #{e.class} - #{e.message}")
        raise ADK::Error, "Calculation failed due to an internal error."
      end
    end # End Calculator class
  end # End Tools module
end # End ADK module
