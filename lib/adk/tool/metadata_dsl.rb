# frozen_string_literal: true

module ADK
  class Tool
    # Module to provide a concise DSL for defining tool metadata in ADK.
    #
    # This module is included by `ADK::Tool` and exposes class-level methods like
    # `tool_description` and `parameter` to define tool capabilities and inputs.
    #
    # @example Defining a custom tool
    #   class MyTool < ADK::Tool
    #     tool_description 'Calculates the square root of a number'
    #
    #     parameter :number,
    #               type: :numeric,
    #               description: 'The number to calculate square root for',
    #               required: true
    #
    #     def perform_execution(params, context)
    #       # ... implementation ...
    #     end
    #   end
    module MetadataDsl
      def self.included(base)
        base.extend ClassMethods

        # Define class instance variable accessors on the base class singleton
        # These are primarily for the *new* DSL
        class << base
          # Replaced attr_accessor with manual methods to handle cache invalidation
          # attr_accessor :explicit_tool_name, :description, :parameters_definition

          def explicit_tool_name
            @explicit_tool_name
          end

          def explicit_tool_name=(value)
            @explicit_tool_name = value
            @_tool_metadata_cache = nil # Invalidate cache
          end

          def description
            @description
          end

          def description=(value)
            @description = value
            @_tool_metadata_cache = nil # Invalidate cache
          end

          def parameters_definition
            @parameters_definition
          end

          def parameters_definition=(value)
            @parameters_definition = value
            @_tool_metadata_cache = nil # Invalidate cache
          end

          # Initialize with default values to ensure methods don't fail on nil
          # Note: These are instance variables of the singleton class (class instance variables)
          def initialize_dsl_storage
            @explicit_tool_name ||= nil
            @description ||= nil # DSL description storage
            @parameters_definition ||= {} # DSL parameters storage
          end
        end
      end

      # Class-level DSL methods extended into tool classes.
      module ClassMethods
        # Sets the description for the tool.
        # This description is used by the LLM planner to understand the tool's purpose.
        #
        # @param text [String] The description of what the tool does.
        # @example
        #   tool_description 'Fetches current weather for a location'
        def tool_description(text)
          initialize_dsl_storage # Ensure vars exist
          self.description = text.to_s
        end

        # Defines a parameter for the tool.
        # Parameters defined here are automatically validated and coerced before
        # execution.
        #
        # @param name [Symbol] The name of the parameter.
        # @param options [Hash] Configuration options for the parameter.
        # @option options [Symbol] :type The expected type (:string, :integer, :float, :numeric, :boolean, :array, :hash).
        # @option options [String] :description A description of the parameter for the LLM.
        # @option options [Boolean] :required (false) Whether the parameter is mandatory.
        #
        # @raise [ArgumentError] if name is not a Symbol.
        #
        # @example Defining a required string parameter
        #   parameter :location, type: :string, description: 'City name', required: true
        #
        # @example Defining an optional boolean parameter
        #   parameter :verbose, type: :boolean, description: 'Enable verbose output', required: false
        def parameter(name, options = {})
          initialize_dsl_storage # Ensure hash exists
          raise ArgumentError, 'Parameter name must be a Symbol' unless name.is_a?(Symbol)

          @parameters_definition[name] = options
          @_tool_metadata_cache = nil # Invalidate cache on modification
        end

        # Infers the tool name from the Ruby class name.
        # Converts CamelCase class names to snake_case symbols (e.g., `MyCustomTool` -> `:my_custom_tool`).
        #
        # @api private
        # @return [Symbol, nil] The inferred tool name, or nil if anonymous class.
        def inferred_name
          class_name_str = Module.instance_method(:name).bind(self).call
          return nil unless class_name_str && !class_name_str.empty? && class_name_str.is_a?(String)
          return nil if class_name_str.start_with?('#<Class:')

          inferred = class_name_str.split('::').last
          return nil if inferred.nil? || inferred.empty?

          inferred = inferred.dup
          inferred.gsub!(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          inferred.gsub!(/([a-z\d])([A-Z])/, '\1_\2')
          inferred.tr!('-', '_')
          inferred.downcase!
          inferred.to_sym
        end

        # Determines the effective name of the tool.
        # Priorities:
        # 1. Explicitly set name via `self.explicit_tool_name=`
        # 2. Name set via deprecated `define_metadata`
        # 3. Name inferred from the class name
        #
        # @return [Symbol, nil] The final tool name.
        def effective_tool_name
          initialize_dsl_storage # Ensure @explicit_tool_name exists
          explicit_dsl = self.explicit_tool_name
          return explicit_dsl if explicit_dsl && explicit_dsl != :''

          # Check define_metadata's variable if explicit DSL name wasn't set
          # Use instance_variable_get as @tool_name is not directly accessible via reader here
          if instance_variable_defined?(:@tool_name)
            explicit_old = instance_variable_get(:@tool_name)
            return explicit_old if explicit_old && explicit_old != :''
          end

          # Fallback to inferred name
          inferred_name
        end

        # Retrieves the consolidated metadata for the tool.
        # Combines name, description, and parameters into a single hash.
        # The result is cached for performance and invalidated when DSL methods are called.
        #
        # @return [Hash] Tool metadata containing :name, :description, and :parameters.
        def tool_metadata
          @_tool_metadata_cache ||= begin
            initialize_dsl_storage # Ensure DSL variables exist

            # Get description: Prefer DSL, fallback to define_metadata's @description
            dsl_desc = self.description
            old_desc = instance_variable_get(:@description) if instance_variable_defined?(:@description) && dsl_desc.nil?
            final_desc = dsl_desc || old_desc

            # Get parameters: Prefer DSL, fallback to define_metadata's @parameters_definition
            dsl_params = self.parameters_definition
            old_params = instance_variable_get(:@parameters_definition) if instance_variable_defined?(:@parameters_definition) && (dsl_params.nil? || dsl_params.empty?)
            final_params = (dsl_params && !dsl_params.empty?) ? dsl_params : (old_params || {})

            {
              name: effective_tool_name,
              description: final_desc,
              parameters: final_params
            }
          end
        end
      end # End ClassMethods
    end
  end
end
