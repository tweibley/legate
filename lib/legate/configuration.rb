# frozen_string_literal: true

require 'legate/agent'
require_relative 'session_service/in_memory'
require 'legate/configuration/webhooks'

module Legate
  # Central configuration object for the Legate framework.
  # Access via `Legate.config` after calling `Legate.configure`.
  class Configuration
    # @return [Legate::SessionService::Base] The service used to manage agent session state.
    attr_accessor :session_service

    # @return [Symbol] Default model name to use if not specified in agent definition.
    attr_accessor :default_model_name

    # @return [Float] Default temperature to use if not specified in agent definition.
    attr_accessor :default_temperature

    # @return [Legate::Configuration::Webhooks] Webhook configuration.
    attr_reader :webhooks

    # @return [Boolean] Whether the web UI may load AI-generated custom tools into
    #   the running process (this executes LLM-generated Ruby — see
    #   Legate::Generators::RuntimeToolLoader). Defaults to ON outside production
    #   and OFF in production. Override explicitly via
    #   `Legate.configure { |c| c.allow_runtime_tool_load = true/false }`.
    attr_accessor :allow_runtime_tool_load

    def initialize
      # Always use in-memory session service (Redis dependency removed)
      @session_service = Legate::SessionService::InMemory.new
      @default_model_name = 'gemini-3.5-flash'
      @default_temperature = 0.7
      @webhooks = Legate::Configuration::Webhooks.new
      @allow_runtime_tool_load = ENV['RACK_ENV'] != 'production'
    end
  end
end
