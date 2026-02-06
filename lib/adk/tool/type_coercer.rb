# frozen_string_literal: true

require 'json'

module ADK
  class Tool
    # Responsible for coercing tool parameters to their expected types.
    class TypeCoercer
      # Error raised when coercion fails.
      class CoercionError < StandardError; end

      # Coerce a value to the expected type.
      # @param value [Object] The value to coerce.
      # @param type [Symbol] The expected type.
      # @return [Object] The coerced value.
      # @raise [CoercionError] If coercion fails.
      def self.coerce(value, type)
        return value if value.nil?

        case type
        when :string
          value.to_s
        when :integer
          coerce_integer(value)
        when :float, :numeric
          coerce_float(value)
        when :boolean
          coerce_boolean(value)
        when :array
          coerce_array(value)
        when :hash
          coerce_hash(value)
        else
          # Unknown type or 'any', return as is
          value
        end
      end

      class << self
        private

        def coerce_integer(value)
          Integer(value)
        rescue ArgumentError, TypeError
          raise CoercionError, "expected Integer, got #{value.class} (#{value.inspect})"
        end

        def coerce_float(value)
          Float(value)
        rescue ArgumentError, TypeError
          raise CoercionError, "expected Numeric/Float, got #{value.class} (#{value.inspect})"
        end

        def coerce_boolean(value)
          if value.is_a?(TrueClass) || value.is_a?(FalseClass)
            value
          elsif value.is_a?(String)
            case value.downcase
            when 'true', 't', 'yes', '1' then true
            when 'false', 'f', 'no', '0' then false
            else
              raise CoercionError, "expected Boolean, got String '#{value}'"
            end
          else
            raise CoercionError, "expected Boolean, got #{value.class} (#{value.inspect})"
          end
        end

        def coerce_array(value)
          if value.is_a?(Array)
            value
          elsif value.is_a?(String)
            begin
              parsed = JSON.parse(value)
              raise CoercionError unless parsed.is_a?(Array)

              parsed
            rescue StandardError
              raise CoercionError, "expected Array, got #{value.class} (#{value.inspect})"
            end
          else
            raise CoercionError, "expected Array, got #{value.class} (#{value.inspect})"
          end
        end

        def coerce_hash(value)
          if value.is_a?(Hash)
            value
          elsif value.is_a?(String)
            begin
              parsed = JSON.parse(value)
              raise CoercionError unless parsed.is_a?(Hash)

              parsed
            rescue StandardError
              raise CoercionError, "expected Hash, got #{value.class} (#{value.inspect})"
            end
          else
            raise CoercionError, "expected Hash, got #{value.class} (#{value.inspect})"
          end
        end
      end
    end
  end
end
