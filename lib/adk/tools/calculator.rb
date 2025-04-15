# File: lib/adk/tools/calculator.rb
# frozen_string_literal: true

require 'logger'
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

      LOGGER = Logger.new($stdout) # Simple logger for potential issues

      def initialize(**options)
        super(**options)
        # No specific initialization needed for this tool
      end

      private

      # Performs the calculation based on validated parameters.
      def perform_execution(params)
        # Remember: params keys are likely strings due to web forms/validation changes
        op1_str = params.fetch('operand1') { params.fetch(:operand1, nil) }
        op2_str = params.fetch('operand2') { params.fetch(:operand2, nil) }
        operation = params.fetch('operation') { params.fetch(:operation, nil) }&.downcase # Normalize operation

        begin
          # Convert operands to Floats for calculation
          # Raise error if conversion fails
          op1 = Float(op1_str)
          op2 = Float(op2_str)
        rescue ArgumentError, TypeError
          LOGGER.error("Calculator Tool: Invalid numeric input received. Operand1: '#{op1_str}', Operand2: '#{op2_str}'")
          raise ADK::Error, "Invalid numeric input provided for operands."
        end

        result = case operation
                 when 'add', '+'
                   op1 + op2
                 when 'subtract', '-'
                   op1 - op2
                 when 'multiply', '*'
                   op1 * op2
                 when 'divide', '/'
                   # Handle division by zero explicitly
                   if op2.zero?
                     raise ADK::Error, "Division by zero is not allowed."
                   else
                     op1 / op2
                   end
                 else
                   LOGGER.warn("Calculator Tool: Unsupported operation '#{operation}' requested.")
                   raise ADK::Error,
                         "Unsupported operation: '#{operation}'. Use add, subtract, multiply, or divide (or +, -, *, /)."
                 end

        # Return the result (could format if needed, but raw number is fine)
        LOGGER.info("Calculator Tool: #{op1} #{operation} #{op2} = #{result}")
        result

      # Catch potential internal errors, though most should be handled above
      rescue StandardError => e
        LOGGER.error("Calculator Tool: Unexpected error during calculation: #{e.class} - #{e.message}")
        # Re-raise or return a specific error message
        raise ADK::Error, "Calculation failed due to an internal error."
      end
    end # End Calculator class
  end # End Tools module
end # End ADK module
