# frozen_string_literal: true

require 'spec_helper'
require 'adk/configuration'

RSpec.describe ADK::Configuration do
  subject(:config) { described_class.new }

  let(:redis_client) { instance_double(Redis) }
  let(:definition_store) { instance_double(ADK::DefinitionStore::RedisStore) }
  let(:session_service) { instance_double(ADK::SessionService::Redis) }
  let(:webhooks_config) { instance_double(ADK::Configuration::Webhooks) }

  before do
    # Mock external dependencies to ensure isolation
    allow(ADK).to receive(:redis_options).and_return({ url: 'redis://mock:6379/0' })
    allow(Redis).to receive(:new).and_return(redis_client)
    allow(ADK::DefinitionStore::RedisStore).to receive(:new).and_return(definition_store)
    allow(ADK::SessionService::Redis).to receive(:new).and_return(session_service)
    allow(ADK::Configuration::Webhooks).to receive(:new).and_return(webhooks_config)
  end

  describe '#initialize' do
    it 'sets default values' do
      expect(config.default_model_name).to eq('gemini-2.5-flash')
      expect(config.default_temperature).to eq(0.7)
    end

    it 'initializes definition_store with Redis store' do
      expect(config.definition_store).to eq(definition_store)
      expect(ADK::DefinitionStore::RedisStore).to have_received(:new).with(redis_client: redis_client)
    end

    it 'initializes session_service with Redis service' do
      expect(config.session_service).to eq(session_service)
      expect(ADK::SessionService::Redis).to have_received(:new)
    end

    it 'initializes webhooks configuration' do
      expect(config.webhooks).to eq(webhooks_config)
    end
  end

  describe 'attribute accessors' do
    it 'allows setting definition_store' do
      new_store = double('NewStore')
      config.definition_store = new_store
      expect(config.definition_store).to eq(new_store)
    end

    it 'allows setting session_service' do
      new_service = double('NewService')
      config.session_service = new_service
      expect(config.session_service).to eq(new_service)
    end

    it 'allows setting default_model_name' do
      config.default_model_name = 'gpt-4'
      expect(config.default_model_name).to eq('gpt-4')
    end

    it 'allows setting default_temperature' do
      config.default_temperature = 0.5
      expect(config.default_temperature).to eq(0.5)
    end

    # Webhooks is attr_reader only in the implementation
    it 'does not allow setting webhooks directly' do
      expect(config).not_to respond_to(:webhooks=)
    end
  end
end
