# File: lib/legate/mcp/util/schema_converter.rb
# frozen_string_literal: true

require 'dry-types' # Ensure dry-types is available for coercion

module Legate
  module Mcp
    module Util
      # Utility class for converting between MCP JSON Schema, Legate Tool parameters,
      # and Dry::Schema definitions.
      class SchemaConverter
        # Converts MCP JSON Schema properties and required array into Legate parameters hash.
        # Handles basic types: string, integer, number, boolean.
        # Logs warnings for unsupported types.
        #
        # @param json_schema_properties [Hash] The 'properties' hash from MCP inputSchema.
        # @param json_schema_required_array [Array<String>] The 'required' array from MCP inputSchema.
        # @return [Hash] Legate parameters hash { name: { type:, required:, description: } }.
        def self.json_to_legate(json_schema_properties, json_schema_required_array = [])
          # Return empty hash if input is invalid or not a Hash
          return {} unless json_schema_properties.is_a?(Hash)

          legate_params = {} # Reverted: Store a hash of param hashes
          required_set = Set.new((json_schema_required_array || []).map(&:to_s))

          json_schema_properties.each do |name, schema|
            # ---> MODIFIED Check: Allow string or symbol key for type <---
            is_valid_schema = schema.is_a?(Hash) && (schema.key?('type') || schema.key?(:type))
            unless is_valid_schema
              Legate.logger.warn("Skipping MCP property '#{name}': Invalid schema format or missing type. Schema: #{schema.inspect}")
              next
            end

            param_name = name.to_sym
            # Determine the type using either key
            schema_type = schema['type'] || schema[:type]
            # Build the inner parameter definition hash
            legate_param_def = {
              # ---> FIX: Check string name in required_set <---
              required: required_set.include?(name.to_s),
              # Use string or symbol key for description
              description: schema['description'] || schema[:description] || ''
            }

            # Determine and add the type to the inner hash based on schema_type
            case schema_type
            when 'string'
              legate_param_def[:type] = :string
            when 'integer'
              legate_param_def[:type] = :integer
            when 'number'
              legate_param_def[:type] = :numeric
            when 'boolean'
              legate_param_def[:type] = :boolean
            when 'array'
              legate_param_def[:type] = :array
            else
              Legate.logger.warn("MCP property '#{name}': Unsupported JSON Schema type '#{schema_type}'. Skipping.")
              next
            end

            # Add the inner hash to the main hash, keyed by param_name
            legate_params[param_name] = legate_param_def
          end

          legate_params # Return the hash of parameter hashes
        end

        # Converts Legate parameters hash into a Proc suitable for Dry::Schema's definition block.
        # Handles basic types: :string, :integer, :numeric, :boolean.
        # Logs warnings for unsupported types.
        #
        # @param legate_parameters_hash [Hash] The Legate parameters hash { name: { type:, required:, description: } }.
        # @return [Proc] A Proc containing the Dry::Schema definition.
        def self.legate_to_dry_schema(legate_parameters_hash)
          Legate.logger.debug("Converting Legate params to Dry::Schema: #{legate_parameters_hash.inspect}")
          return proc {} unless legate_parameters_hash.is_a?(Hash)

          schema_lines = []

          legate_parameters_hash.each do |name, definition|
            unless definition.is_a?(Hash) && definition[:type]
              Legate.logger.warn("Skipping Legate parameter '#{name}': Invalid definition format or missing type.")
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
              Legate.logger.warn("Legate parameter '#{name}': Type :array basic mapping to Dry::Schema. Item types/validation not processed in V1.")
              dry_type_method = 'value'
              type_spec = ':array'
            when :hash, :object
              Legate.logger.warn("Legate parameter '#{name}': Type :#{definition[:type]} basic mapping to Dry::Schema :hash. Nested schema not processed in V1.")
              dry_type_method = 'value'
              type_spec = ':hash'
            else
              Legate.logger.warn("Legate parameter '#{name}': Unsupported Legate type '#{definition[:type]}'. Skipping.")
              next
            end

            # Build the line
            line = "  #{required_or_optional}(:#{name})"
            line += ".#{dry_type_method}" if dry_type_method
            line += "(#{type_spec})" # Add the type specifier

            schema_lines << line
          end

          schema_definition_string = schema_lines.join("\n")
          Legate.logger.debug("Generated Dry::Schema definition string:\n#{schema_definition_string}")

          proc { instance_eval(schema_definition_string) }
        end
      end
    end
  end
end
