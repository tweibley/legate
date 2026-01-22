# frozen_string_literal: true

module ADK
  class Tool
    # Module to provide a more concise DSL for defining tool metadata.
    module MetadataDsl
      def self.included(base)
        base.extend ClassMethods

        # Define class instance variable accessors on the base class singleton
        # These are primarily for the *new* DSL
        class << base
          # Accessors for DSL storage
          attr_reader :explicit_tool_name, :description, :parameters_definition

          def explicit_tool_name=(value)
            @explicit_tool_name = value
            @tool_metadata = nil # Invalidate cache
          end

          def description=(value)
            @description = value
            @tool_metadata = nil # Invalidate cache
          end

          def parameters_definition=(value)
            @parameters_definition = value
            @tool_metadata = nil # Invalidate cache
          end

          # Initialize with default values to ensure methods don't fail on nil
          # Note: These are instance variables of the singleton class (class instance variables)
          # rubocop:disable Naming/MemoizedInstanceVariableName
          def initialize_dsl_storage
            @explicit_tool_name ||= nil
            @description ||= nil # DSL description storage
            @parameters_definition ||= {} # DSL parameters storage
          end
          # rubocop:enable Naming/MemoizedInstanceVariableName
        end
      end

      # Class methods mixed into the Tool class
      module ClassMethods
        # Sets the description of the tool.
        # This description is used by the Agent (and its Planner) to understand what the tool does
        # and when to select it during planning. Clear, concise descriptions improve agent performance.
        #
        # @param text [String] A description of the tool's purpose and functionality.
        # @example
        #   tool_description "Calculates the sum of two numbers."
        def tool_description(text)
          initialize_dsl_storage # Ensure vars exist
          self.description = text.to_s
        end

        # Defines a parameter for the tool.
        # Parameters are automatically validated and coerced into the specified types
        # before the tool's execution logic is called.
        #
        # @param name [Symbol] The name of the parameter.
        # @param options [Hash] Configuration options for the parameter.
        # @option options [Symbol] :type The expected type of the parameter. Supported types:
        #   `:string`, `:integer`, `:float`, `:boolean`, `:array`, `:hash`.
        # @option options [Boolean] :required (false) Whether the parameter is mandatory.
        # @option options [String] :description A description of the parameter, used by the LLM
        #   to understand what value to provide.
        #
        # @raise [ArgumentError] if the parameter name is not a Symbol.
        #
        # @example Defining a required string parameter
        #   parameter :location, type: :string, required: true, description: "City name"
        #
        # @example Defining an optional integer parameter
        #   parameter :limit, type: :integer, description: "Max results to return"
        #
        # @example Defining a boolean flag
        #   parameter :verbose, type: :boolean, description: "Enable verbose output"
        def parameter(name, options = {})
          initialize_dsl_storage # Ensure hash exists
          raise ArgumentError, 'Parameter name must be a Symbol' unless name.is_a?(Symbol)

          @parameters_definition[name] = options
          @tool_metadata = nil # Invalidate cache on modification
        end

        # Get the inferred name (logic unchanged)
        # @api private
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

        # Get the final tool name with priority:
        # 1. DSL's explicit_tool_name
        # 2. define_metadata's @tool_name
        # 3. Inferred name
        # @api private
        def effective_tool_name
          initialize_dsl_storage # Ensure @explicit_tool_name exists
          explicit_dsl = explicit_tool_name
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

        # Retrieve consolidated metadata, preferring DSL values but falling back to define_metadata values.
        # Cached for performance.
        # @api private
        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def tool_metadata
          @tool_metadata ||= begin
            initialize_dsl_storage # Ensure DSL variables exist

            # Get description: Prefer DSL, fallback to define_metadata's @description
            dsl_desc = description
            old_desc = instance_variable_get(:@description) if instance_variable_defined?(:@description) && dsl_desc.nil?
            final_desc = dsl_desc || old_desc

            # Get parameters: Prefer DSL, fallback to define_metadata's @parameters_definition
            dsl_params = parameters_definition
            old_params = instance_variable_get(:@parameters_definition) if instance_variable_defined?(:@parameters_definition) && (dsl_params.nil? || dsl_params.empty?)
            final_params = dsl_params && !dsl_params.empty? ? dsl_params : (old_params || {})

            {
              name: effective_tool_name,
              description: final_desc,
              parameters: final_params
            }
          end
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      end # End ClassMethods
    end
  end
end
