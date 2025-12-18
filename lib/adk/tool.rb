# File: lib/adk/tool.rb
# frozen_string_literal: true

require_relative 'tool_registry'
require 'logger'
require_relative 'tool_context'
require_relative 'global_tool_manager'
require_relative 'tool/metadata_dsl'

module ADK
  class Tool
    # --- Include the DSL ---
    include MetadataDsl

    # --- Class-level attributes --- Accessors defined via DSL, but keep old readers/define_metadata for backward compat ---
    class << self
      # Keep old readers for define_metadata compatibility
      attr_reader :tool_name, :description, :parameters_definition

      # Define the tool's static metadata.
      # DEPRECATED: Use `tool_description`, `parameter`, and automatic name inference instead.
      def define_metadata(name:, description:, parameters: {})
        warn "[DEPRECATION] `define_metadata` is deprecated. Use `tool_description`, `parameter`, and rely on class name inference (or `self.explicit_tool_name = :my_name`) instead. Called from #{caller_locations(
          1, 1
        )[0].label}"

        @tool_name = name.to_sym
        @description = description
        @parameters_definition = parameters
        @_tool_metadata_cache = nil # Invalidate cache
      end

      # --- Fallback Metadata Method (Commented out as DSL version takes precedence) ---
      # def tool_metadata
      #   ...
      # end
      # --- End Fallback Metadata Method ---
    end # End Class-level
    # --- End Class-level ---

    # --- Self-Registration Hook ---
    # NOTE: We intentionally do NOT auto-register tools in the inherited hook.
    # The reason is that `inherited` is called BEFORE the class body executes,
    # so explicit_tool_name and other DSL methods haven't run yet. This would
    # cause tools to be registered under their inferred name (e.g., :random_number_tool)
    # instead of their explicit name (e.g., :random_number).
    #
    # Instead, built-in tools are explicitly registered in lib/adk.rb after their
    # class definitions are complete. Custom tools should either:
    # 1. Call `ADK::GlobalToolManager.register_tool(MyTool)` explicitly after definition
    # 2. Be discovered via tool_paths when creating agents
    def self.inherited(subclass)
      super # Call parent's inherited if necessary
      ADK.logger.debug("Tool subclass #{subclass} inherited. Tool will be registered when explicitly added to GlobalToolManager or an agent's tool registry.")
    end
    # --- End Hook ---

    # Instance readers
    attr_reader :name, :description, :parameters

    # Initialize - Sets instance vars from class metadata
    def initialize(**_options)
      # Fetch metadata using the primary tool_metadata method (defined by DSL)
      metadata = self.class.tool_metadata
      @name = metadata[:name]
      @description = metadata[:description]
      @parameters = metadata[:parameters] || {}

      # Lenient check for missing metadata
      if @name.nil? || @name == :'' || @description.nil? || @description.empty?
        is_anonymous = !self.class.name || self.class.name.empty? || self.class.name.start_with?('#<Class:')
        unless is_anonymous
          missing = []
          missing << ':name' if @name.nil? || @name == :''
          missing << ':description' if @description.nil? || @description.empty?
          ADK.logger.warn("Tool class #{self.class} initialized with missing metadata: [#{missing.join(', ')}] using #{self.class.tool_metadata}. Tool may not function correctly.")
        end
        @description ||= ''
      end
    end

    # Execute the tool
    # @param params [Hash] Input parameters for the tool.
    # @param context [ADK::ToolContext, nil] Contextual information (session details).
    # @return [Hash] A hash with :status (:success, :error, :pending) and :result/:error_message/:workflow_id.
    def execute(params = {}, context = nil)
      validate_params(params)
      ADK.logger.debug("Executing tool '#{@name}' with validated params: #{params.inspect} and context: #{context&.to_h.inspect}")
      perform_execution(params, context)
    end

    # Validate the parameters
    def validate_params(params)
      current_parameters = @parameters || {}
      required_param_names = current_parameters.select { |_, p| p[:required] }.keys.map(&:to_s)
      present_keys = params.keys.map(&:to_s)
      missing_params = required_param_names - present_keys
      unless missing_params.empty?
        log_message = "Validation failed for tool '#{@name}'. Required(string): #{required_param_names.inspect}, Received keys(string): #{present_keys.inspect}, Received params: #{params.inspect}"
        ADK.logger.error(log_message)
        raise ADK::ToolArgumentError, "Missing required parameters: #{missing_params.join(', ')}"
      end
    end

    private

    # Perform the actual execution of the tool
    # @param params [Hash] The validated parameters to execute with
    # @param context [ADK::ToolContext, nil] Contextual information (session details).
    # @return [Object] The result of the execution
    def perform_execution(params, context)
      raise NotImplementedError, 'Subclasses must implement #perform_execution(params, context)'
    end
  end
end
