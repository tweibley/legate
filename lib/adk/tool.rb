# File: lib/adk/tool.rb
# frozen_string_literal: true

require_relative 'tool_registry'
require 'logger'
require_relative 'tool_context'
require_relative 'global_tool_manager'

module ADK
  class Tool
    # --- Class-level attributes ---
    class << self
      attr_reader :tool_name, :description, :parameters_definition

      # Define the tool's static metadata.
      # This now ALSO registers the tool globally.
      def define_metadata(name:, description:, parameters: {})
        @tool_name = name.to_sym
        @description = description
        @parameters_definition = parameters
        ADK::GlobalToolManager.register_tool(self)
      end

      # --- ADDED: Method to retrieve all metadata as a hash ---
      def tool_metadata
        {
          name: @tool_name,
          description: @description,
          parameters: @parameters_definition
        }
      end
      # --- End ADDED ---

      # --- REMOVED Registration Logic Method ---
      # def register_tool_class
      #   ...
      # end
      # --- End REMOVED Registration Logic Method ---
    end
    # --- End Class-level ---

    # --- Self-Registration Hook (No longer functional, can be removed or left as is) ---
    def self.inherited(subclass)
      super # Call parent's inherited if necessary
      # The registration now happens when define_metadata is called in the subclass
      ADK.logger.debug("Tool subclass #{subclass} inherited from ADK::Tool.")
      # Registration now triggered by define_metadata in subclass
    end
    # --- End Hook ---

    # Instance readers
    attr_reader :name, :description, :parameters

    # Initialize - Sets instance vars from class metadata
    def initialize(**_options)
      @name = self.class.tool_name
      @description = self.class.description
      @parameters = self.class.parameters_definition || {}

      unless @name && @description
        raise ArgumentError, "Tool class #{self.class} must define :name and :description using `define_metadata`."
      end

      # --- REMOVED registration call from initialize ---
      # self.class.register_tool_class
    end

    # Execute the tool
    # @param params [Hash] Input parameters for the tool.
    # @param context [ADK::ToolContext, nil] Contextual information (session details).
    # @return [Hash] A hash with :status (:success, :error, :pending) and :result/:error_message/:workflow_id.
    def execute(params = {}, context = nil)
      validate_params(params)
      # Log parameters *after* validation succeeds but before execution
      ADK.logger.debug("Executing tool '#{name}' with validated params: #{params.inspect} and context: #{context&.to_h.inspect}")
      # Pass context to perform_execution
      perform_execution(params, context)
    end

    # Validate the parameters
    def validate_params(params)
      # ... (validation logic remains the same) ...
      required_param_names = @parameters.select { |_, p| p[:required] }.keys.map(&:to_s)
      present_keys = params.keys.map(&:to_s)
      missing_params = required_param_names - present_keys
      unless missing_params.empty?
        # --- Use the central ADK logger here ---
        log_message = "Validation failed for tool '#{@name}'. Required(string): #{required_param_names.inspect}, Received keys(string): #{present_keys.inspect}, Received params: #{params.inspect}"
        ADK.logger.error(log_message) # Log the specific error
        # --- End logger usage ---
        # Raise the error with just the user-facing message
        raise ADK::Error, "Missing required parameters: #{missing_params.join(', ')}"
      end
      # Optional: Add type validation here later if needed
    end

    private

    # Perform the actual execution of the tool
    # @param params [Hash] The validated parameters to execute with
    # @param context [ADK::ToolContext, nil] Contextual information (session details).
    # @return [Object] The result of the execution
    def perform_execution(params, context)
      raise NotImplementedError, "Subclasses must implement #perform_execution(params, context)"
    end
  end
end
