# File: lib/adk/definition_store.rb
# frozen_string_literal: true

require_relative 'definition_store/redis_store' # Future implementation

module ADK
  # Module responsible for persisting and retrieving agent definitions.
  # Implementations should provide methods for CRUD operations on definitions.
  module DefinitionStore
    # NOTE: Base error classes (Error, ConfigurationError, StoreError)
    # are defined in lib/adk/errors.rb and inherit from ADK::Error.

    # Error raised when a definition is not found
    # Inherits from ADK::DefinitionStore::Error defined in errors.rb
    class NotFoundError < Error; end # Use the base Error defined in errors.rb (ADK::DefinitionStore::Error)

    # Removing redundant/conflicting definitions:
    # class StoreError < StandardError; end
    # class ConfigurationError < StoreError; end

    # Potential future: Define abstract methods or rely on duck typing for implementations.

    # Example of how an implementation might be instantiated (though likely done in App)
    # def self.create_store(config = { type: :redis })
    #   case config[:type]
    #   when :redis
    #     # Requires Redis connection details
    #     RedisStore.new(config[:connection] || Redis.new)
    #   # when :file
    #   #   FileStore.new(config[:path]) # Hypothetical
    #   else
    #     raise ConfigurationError, "Unsupported definition store type: #{config[:type]}"
    #   end
    # end
  end
end
