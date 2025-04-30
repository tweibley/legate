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
          attr_accessor :explicit_tool_name, :description, :parameters_definition

          # Initialize with default values to ensure methods don't fail on nil
          # Note: These are instance variables of the singleton class (class instance variables)
          def initialize_dsl_storage
            @explicit_tool_name ||= nil
            @description ||= nil # DSL description storage
            @parameters_definition ||= {} # DSL parameters storage
          end
        end
      end

      module ClassMethods
        # DSL method for setting description
        def tool_description(text)
          initialize_dsl_storage # Ensure vars exist
          self.description = text.to_s
        end

        # DSL method for defining a parameter
        def parameter(name, options = {})
          initialize_dsl_storage # Ensure hash exists
          raise ArgumentError, "Parameter name must be a Symbol" unless name.is_a?(Symbol)

          @parameters_definition[name] = options
        end

        # Get the inferred name (logic unchanged)
        def inferred_name
          class_name_str = Module.instance_method(:name).bind(self).call
          return nil unless class_name_str && !class_name_str.empty? && class_name_str.is_a?(String)
          return nil if class_name_str.start_with?('#<Class:')

          inferred = class_name_str.split('::').last
          return nil if inferred.nil? || inferred.empty?

          inferred = inferred.dup
          inferred.gsub!(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          inferred.gsub!(/([a-z\d])([A-Z])/, '\1_\2')
          inferred.tr!("-", "_")
          inferred.downcase!
          inferred.to_sym
        end

        # Get the final tool name with priority:
        # 1. DSL's explicit_tool_name
        # 2. define_metadata's @tool_name
        # 3. Inferred name
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

        # Retrieve consolidated metadata, preferring DSL values but falling back to define_metadata values.
        def tool_metadata
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
      end # End ClassMethods
    end
  end
end
