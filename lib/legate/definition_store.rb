# File: lib/legate/definition_store.rb
# frozen_string_literal: true

module Legate
  # Module responsible for persisting and retrieving agent definitions.
  # Implementations should provide methods for CRUD operations on definitions.
  module DefinitionStore
    # NOTE: Base error classes (Error, ConfigurationError, StoreError)
    # are defined in lib/legate/errors.rb and inherit from Legate::Error.

    # Error raised when a definition is not found
    # Inherits from Legate::DefinitionStore::Error defined in errors.rb
    class NotFoundError < Error; end # Use the base Error defined in errors.rb (Legate::DefinitionStore::Error)

    # Removing redundant/conflicting definitions:
    # class StoreError < StandardError; end
    # class ConfigurationError < StoreError; end

    # Potential future: Define abstract methods or rely on duck typing for implementations.

    # Definitions are stored in-memory via GlobalDefinitionRegistry.
  end
end
