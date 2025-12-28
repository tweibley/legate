# frozen_string_literal: true

require 'spec_helper'
require 'adk/configuration'

RSpec.describe ADK::Configuration do
  subject(:config) { described_class.new }

  # Mock ADK.redis_options to avoid Sidekiq configuration errors
  before do
    allow(ADK).to receive(:redis_options).and_return({ url: 'redis://localhost:6379/0' })
    allow(Redis).to receive(:new).and_return(instance_double(Redis))
    allow(ADK::DefinitionStore::RedisStore).to receive(:new).and_return(instance_double(ADK::DefinitionStore::RedisStore))
    allow(ADK::SessionService::Redis).to receive(:new).and_return(instance_double(ADK::SessionService::Redis))
  end

  describe '#initialize' do
    it 'initializes definition_store with RedisStore' do
      config # Trigger initialization
      expect(ADK::DefinitionStore::RedisStore).to have_received(:new)
    end

    it 'initializes session_service with Redis' do
      config # Trigger initialization
      expect(ADK::SessionService::Redis).to have_received(:new)
    end

    it 'sets default model name' do
      expect(config.default_model_name).to eq('gemini-2.5-flash')
    end

    it 'sets default temperature' do
      expect(config.default_temperature).to eq(0.7)
    end

    it 'initializes webhooks configuration' do
      expect(config.webhooks).to be_a(ADK::Configuration::Webhooks)
    end
  end
end
