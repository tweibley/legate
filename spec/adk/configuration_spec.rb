# frozen_string_literal: true

require 'spec_helper'
require 'adk/configuration'

RSpec.describe ADK::Configuration do
  describe 'Lazy Loading' do
    it 'does NOT instantiate Redis eagerly on initialization' do
      # We expect Redis.new NOT to be called when we create a Configuration object
      expect(Redis).not_to receive(:new)

      # This assumes ADK.redis_options is available.
      allow(ADK).to receive(:redis_options).and_return({ url: 'redis://localhost:6379/0' })

      config = ADK::Configuration.new

      # Verify defaults are set
      expect(config.default_model_name).to eq('gemini-2.5-flash')
    end

    it 'instantiates Redis only when accessed' do
      allow(ADK).to receive(:redis_options).and_return({ url: 'redis://localhost:6379/0' })

      config = ADK::Configuration.new

      # Now expect it to be called
      expect(Redis).to receive(:new).at_least(:once).and_call_original

      # Accessing the property triggers the lazy load
      expect(config.definition_store).to be_a(ADK::DefinitionStore::RedisStore)
    end
  end
end
