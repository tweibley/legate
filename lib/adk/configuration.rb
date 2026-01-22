# frozen_string_literal: true

require 'adk/agent'
require 'redis' # Required for RedisStore
require_relative 'definition_store/redis_store' # Require the actual store
require_relative 'session_service/redis' # Use Redis for session persistence
require 'adk/configuration/webhooks'

module ADK
  # Central configuration object for the ADK framework.
  # Access via `ADK.config` after calling `ADK.configure`.
  class Configuration
    # @return [ADK::DefinitionStore::Base] The store used to load agent definitions.
    attr_writer :definition_store

    # @return [ADK::SessionService::Base] The service used to manage agent session state.
    attr_writer :session_service

    # @return [Symbol] Default model name to use if not specified in agent definition.
    attr_accessor :default_model_name

    # @return [Float] Default temperature to use if not specified in agent definition.
    attr_accessor :default_temperature

    # @return [ADK::Configuration::Webhooks] Webhook configuration.
    attr_reader :webhooks

    def initialize
      # Set defaults
      # Note: definition_store and session_service are now lazy-initialized
      @default_model_name = 'gemini-2.5-flash'
      @default_temperature = 0.7
      @webhooks = ADK::Configuration::Webhooks.new
    end

    def definition_store
      @definition_store ||= ADK::DefinitionStore::RedisStore.new(redis_client: Redis.new(ADK.redis_options))
    end

    def session_service
      @session_service ||= ADK::SessionService::Redis.new
    end
  end
end
