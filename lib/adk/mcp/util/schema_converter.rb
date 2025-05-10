# File: lib/adk/mcp/util/schema_converter.rb
# frozen_string_literal: true

require 'set' # Needed for json_to_adk
require 'dry-types' # Ensure dry-types is available for coercion

module ADK
  module Mcp
    module Util
      # Utility class for converting between MCP JSON Schema, ADK Tool parameters,
      # and Dry::Schema definitions.
      class SchemaConverter
        # Converts MCP JSON Schema properties and required array into ADK parameters hash.
        # Handles basic types: string, integer, number, boolean.
        # Logs warnings for unsupported types.
        #
        # @param json_schema_properties [Hash] The 'properties' hash from MCP inputSchema.
        # @param json_schema_required_array [Array<String>] The 'required' array from MCP inputSchema.
        # @return [Hash] ADK parameters hash { name: { type:, required:, description: } }.
        def self.json_to_adk(json_schema_properties, json_schema_required_array = [])
          # Return empty hash if input is invalid or not a Hash
          return {} unless json_schema_properties.is_a?(Hash)

          adk_params = {} # Reverted: Store a hash of param hashes
          required_set = Set.new((json_schema_required_array || []).map(&:to_s))

          json_schema_properties.each do |name, schema|
            # ---> MODIFIED Check: Allow string or symbol key for type <---
            is_valid_schema = schema.is_a?(Hash) && (schema.key?('type') || schema.key?(:type))
            unless is_valid_schema
              # <-------------------------------------------------------->
              ADK.logger.warn("Skipping MCP property '#{name}': Invalid schema format or missing type. Schema: #{schema.inspect}")
              next
            end

            param_name = name.to_sym
            # Determine the type using either key
            schema_type = schema['type'] || schema[:type]
            # Build the inner parameter definition hash
            adk_param_def = {
              # ---> FIX: Check string name in required_set <---
              required: required_set.include?(name.to_s),
              # <------------------------------------------->
              # Use string or symbol key for description
              description: schema['description'] || schema[:description] || ''
            }

            # Determine and add the type to the inner hash based on schema_type
            case schema_type
            when 'string'
              adk_param_def[:type] = :string
            when 'integer'
              adk_param_def[:type] = :integer
            when 'number'
              adk_param_def[:type] = :numeric
            when 'boolean'
              adk_param_def[:type] = :boolean
            when 'array'
              adk_param_def[:type] = :array
            else
              ADK.logger.warn("MCP property '#{name}': Unsupported JSON Schema type '#{schema_type}'. Skipping.")
              next
            end

            # Add the inner hash to the main hash, keyed by param_name
            adk_params[param_name] = adk_param_def
          end

          adk_params # Return the hash of parameter hashes
        end

        # Converts ADK parameters hash into a Proc suitable for Dry::Schema's definition block.
        # Handles basic types: :string, :integer, :numeric, :boolean.
        # Logs warnings for unsupported types.
        #
        # @param adk_parameters_hash [Hash] The ADK parameters hash { name: { type:, required:, description: } }.
        # @return [Proc] A Proc containing the Dry::Schema definition.
        def self.adk_to_dry_schema(adk_parameters_hash)
          ADK.logger.debug("Converting ADK params to Dry::Schema: #{adk_parameters_hash.inspect}")
          return proc {} unless adk_parameters_hash.is_a?(Hash)

          schema_lines = []

          adk_parameters_hash.each do |name, definition|
            unless definition.is_a?(Hash) && definition[:type]
              ADK.logger.warn("Skipping ADK parameter '#{name}': Invalid definition format or missing type.")
              next
            end

            required_or_optional = definition[:required] ? 'required' : 'optional'
            dry_type_method = nil
            type_spec = nil

            case definition[:type]
            when :string
              dry_type_method = 'filled'
              type_spec = ':string'
            when :integer
              dry_type_method = 'filled'
              type_spec = ':integer'
            when :numeric
              # Use coercible float type to handle string inputs that represent numbers
              dry_type_method = 'filled'
              type_spec = 'Dry::Types[\'coercible.float\']'
            when :boolean
              dry_type_method = 'filled'
              type_spec = ':bool'
            when :array
              ADK.logger.warn("ADK parameter '#{name}': Type :array basic mapping to Dry::Schema. Item types/validation not processed in V1.")
              dry_type_method = 'value'
              type_spec = ':array'
            when :hash, :object
              ADK.logger.warn("ADK parameter '#{name}': Type :#{definition[:type]} basic mapping to Dry::Schema :hash. Nested schema not processed in V1.")
              dry_type_method = 'value'
              type_spec = ':hash'
            else
              ADK.logger.warn("ADK parameter '#{name}': Unsupported ADK type '#{definition[:type]}'. Skipping.")
              next
            end

            # Build the line
            line = "  #{required_or_optional}(:#{name})"
            line += ".#{dry_type_method}" if dry_type_method
            line += "(#{type_spec})" # Add the type specifier

            schema_lines << line
          end

          schema_definition_string = schema_lines.join("\n")
          ADK.logger.debug("Generated Dry::Schema definition string:\n#{schema_definition_string}")

          proc { instance_eval(schema_definition_string) }
        end
      end
    end
  end
end
