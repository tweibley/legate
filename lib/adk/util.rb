# frozen_string_literal: true

module ADK
  module Util
    # Creates a deep copy of an object, preserving symbols.
    # Replaces the unsafe Marshal.load(Marshal.dump(obj)) pattern.
    #
    # @param obj [Object] The object to deep copy (Hash, Array, String, or other)
    # @return [Object] A deep copy of the object
    def self.deep_copy(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_copy(v) }
      when Array
        obj.map { |v| deep_copy(v) }
      when String
        obj.dup
      else
        obj # frozen or immediate values (Integer, Symbol, etc.)
      end
    end
  end
end
