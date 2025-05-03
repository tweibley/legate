require 'adk/agent'
require 'redis' # Required for RedisStore
require_relative 'definition_store/redis_store' # Require the actual store
require_relative 'session_service/in_memory' # Corrected path
require 'adk/configuration/webhooks'

module ADK
  # Central configuration object for the ADK framework.
  # Access via `ADK.config` after calling `ADK.configure`.
  class Configuration
    # @return [ADK::DefinitionStore::Base] The store used to load agent definitions.
    attr_accessor :definition_store

    # @return [ADK::SessionService::Base] The service used to manage agent session state.
    attr_accessor :session_service

    # @return [Symbol] Default model name to use if not specified in agent definition.
    attr_accessor :default_model_name

    # @return [Float] Default temperature to use if not specified in agent definition.
    attr_accessor :default_temperature

    # @return [ADK::Configuration::Webhooks] Webhook configuration.
    attr_reader :webhooks

    def initialize
      # Set defaults
      @definition_store = ADK::DefinitionStore::RedisStore.new(Redis.new(ADK.redis_options))
      @session_service = ADK::SessionService::InMemory.new
      @default_model_name = 'gemini-1.5-flash'
      @default_temperature = 0.7
      @webhooks = ADK::Configuration::Webhooks.new
    end
  end
end 