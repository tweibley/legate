# File: lib/adk/tool.rb
# frozen_string_literal: true

require_relative 'tool_registry'
require 'logger'

module ADK
  class Error < StandardError; end

  class Error < StandardError; end

  class Tool
    # --- Class-level attributes ---
    class << self
      attr_reader :tool_name, :description, :parameters_definition

      def define_metadata(name:, description:, parameters: {})
        @tool_name = name.to_sym
        @description = description
        @parameters_definition = parameters
        # --- Trigger registration AFTER metadata is defined ---
        register_tool_class
      end

      # --- Moved Registration Logic Here ---
      def register_tool_class
        unless @tool_name && @description # Check if metadata was set
          # Don't log error here, might be called for base class
          # Logger.new($stdout).error("ToolRegistry: Cannot register #{self}. Metadata not defined via `define_metadata`.")
          return
        end

        # Prevent re-registration if already done (optional, register overwrites anyway)
        # unless ADK::ToolRegistry.find_class(@tool_name) == self
        ADK::ToolRegistry.register(@tool_name, self)
        # end
      end
      # --- End Moved Registration Logic ---
    end
    # --- End Class-level ---

    # --- Self-Registration Hook (Now less critical but harmless) ---
    def self.inherited(subclass)
      super # Call parent's inherited if necessary
      # The registration now happens when define_metadata is called in the subclass
      Logger.new($stdout).debug("Tool subclass #{subclass} inherited from ADK::Tool.")
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

    # --- Add Class method to handle registration ---
    def self.register_tool_class
      unless @tool_name && @description && @parameters_definition
        Logger.new($stdout).error("ToolRegistry: Cannot register #{self}. Metadata not defined via `define_metadata`.")
        return
      end
      # Prevent re-registration if already done
      unless ADK::ToolRegistry.find_class(@tool_name) == self
        ADK::ToolRegistry.register(@tool_name, self)
      end
    end
    # --- End Class method ---

    # Execute the tool
    def execute(params = {})
      validate_params(params)
      perform_execution(params)
    end

    # Validate the parameters
    def validate_params(params)
      # ... (validation logic remains the same) ...
      required_param_names = @parameters.select { |_, p| p[:required] }.keys.map(&:to_s)
      present_keys = params.keys.map(&:to_s)
      missing_params = required_param_names - present_keys
      unless missing_params.empty?
        logger = self.respond_to?(:logger) ? self.logger : Logger.new($stdout)
        logger.error("Validation failed. Required(string): #{required_param_names.inspect}, Received keys(string): #{present_keys.inspect}, Received params: #{params.inspect}")
        raise Error, "Missing required parameters: #{missing_params.join(', ')}"
      end
    end

    private

    def perform_execution(params)
      raise NotImplementedError, "Subclasses must implement #perform_execution"
    end
  end
end
