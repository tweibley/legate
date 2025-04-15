# frozen_string_literal: true

module ADK
  # Tool class represents a tool that an agent can use
  class Tool
    attr_reader :name, :description, :parameters

    # Initialize a new tool
    # @param name [String] The name of the tool
    # @param description [String] A description of the tool
    # @param parameters [Hash] The parameters the tool accepts
    def initialize(name:, description:, parameters: {})
      @name = name
      @description = description
      @parameters = parameters
    end

    # Execute the tool with the given parameters
    # @param params [Hash] The parameters to execute the tool with
    # @return [Object] The result of the tool execution
    def execute(params = {})
      validate_params(params)
      perform_execution(params)
    end

    # Validate the parameters
    # @param params [Hash] The parameters to validate (EXPECTS STRING KEYS NOW)
    # @raise [Error] If the parameters are invalid
    def validate_params(params)
        # Get required parameter names AS STRINGS
        required_param_names = parameters.select { |_, p| p[:required] }.keys.map(&:to_s)
  
        # Check against the keys in the input params hash (which are likely strings)
        present_keys = params.keys.map(&:to_s) # Ensure we compare strings to strings
  
        missing_params = required_param_names - present_keys
  
        unless missing_params.empty?
          # Log the params received during failure for debugging
          # Use the logger defined in the specific tool instance if available
          logger = self.respond_to?(:logger) ? self.logger : Logger.new($stdout)
          logger.error("Validation failed. Required(string): #{required_param_names.inspect}, Received keys(string): #{present_keys.inspect}, Received params: #{params.inspect}")
  
          raise Error, "Missing required parameters: #{missing_params.join(', ')}"
        end
      end

    private

    # Perform the actual execution of the tool
    # @param params [Hash] The parameters to execute with
    # @return [Object] The result of the execution
    def perform_execution(params)
      raise NotImplementedError, "Subclasses must implement #perform_execution"
    end
  end
end 