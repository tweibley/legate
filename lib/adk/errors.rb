# File: lib/adk/errors.rb
# frozen_string_literal: true

module ADK
  class Error < StandardError; end

  # Raised when state validation fails
  class StateValidationError < Error; end

  # Raised when an invalid prefix is used in state keys
  class InvalidPrefixError < Error; end

  # Raised when state value cannot be serialized
  class SerializationError < Error; end

  # Raised when attempting to modify state directly
  class StateAccessError < Error; end
end
