# File: lib/adk/definition_store.rb
# frozen_string_literal: true

require_relative 'definition_store/redis_store' # Future implementation

module ADK
  # Module responsible for persisting and retrieving agent definitions.
  # Implementations should provide methods for CRUD operations on definitions.
  module DefinitionStore
    # Base error class for definition store issues
    class StoreError < StandardError; end

    # Error raised when a definition is not found
    class NotFoundError < StoreError; end

    # Error raised for configuration or connection issues
    class ConfigurationError < StoreError; end

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
