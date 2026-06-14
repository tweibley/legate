# File: lib/legate/llm.rb
# frozen_string_literal: true

require_relative 'llm/adapter'
require_relative 'llm/gemini'
require_relative 'llm/ollama'

module Legate
  module LLM
    class << self
      # A factory for the default LLM adapter, called as
      # `factory.call(model:, api_key:, logger:)` and expected to return a
      # Legate::LLM::Adapter. Set this to use a provider other than Gemini for
      # every agent, e.g.:
      #   Legate::LLM.default_adapter_factory = ->(model:, api_key:, logger:) {
      #     MyProvider::Adapter.new(model: model, logger: logger)
      #   }
      # Nil means use the built-in Gemini adapter.
      # @return [#call, nil]
      attr_accessor :default_adapter_factory
    end

    # Builds an adapter using the configured factory, or the default Gemini
    # adapter. Per-planner overrides take precedence over this.
    # @return [Legate::LLM::Adapter]
    def self.build_adapter(model:, api_key: nil, logger: nil)
      if default_adapter_factory
        default_adapter_factory.call(model: model, api_key: api_key, logger: logger)
      else
        Gemini.new(model: model, api_key: api_key, logger: logger)
      end
    end
  end
end
