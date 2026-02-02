# frozen_string_literal: true

require 'spec_helper'
require 'adk/configuration'

RSpec.describe ADK::Configuration do
  subject(:config) { described_class.new }

  let(:mock_redis) { instance_double(Redis) }
  let(:mock_definition_store) { instance_double(ADK::DefinitionStore::RedisStore) }
  let(:mock_session_service) { instance_double(ADK::SessionService::Redis) }
  let(:mock_webhooks_config) { instance_double(ADK::Configuration::Webhooks) }

  before do
    allow(Redis).to receive(:new).and_return(mock_redis)
    allow(ADK::DefinitionStore::RedisStore).to receive(:new).and_return(mock_definition_store)
    allow(ADK::SessionService::Redis).to receive(:new).and_return(mock_session_service)
    allow(ADK::Configuration::Webhooks).to receive(:new).and_return(mock_webhooks_config)
  end

  describe '#initialize' do
    it 'sets default values' do
      expect(config.default_model_name).to eq('gemini-2.5-flash')
      expect(config.default_temperature).to eq(0.7)
    end

    it 'initializes definition store with redis client' do
      expect(ADK::DefinitionStore::RedisStore).to receive(:new).with(redis_client: mock_redis).and_return(mock_definition_store)
      expect(config.definition_store).to eq(mock_definition_store)
    end

    it 'initializes session service' do
      expect(ADK::SessionService::Redis).to receive(:new).and_return(mock_session_service)
      expect(config.session_service).to eq(mock_session_service)
    end

    it 'initializes webhooks configuration' do
      expect(ADK::Configuration::Webhooks).to receive(:new).and_return(mock_webhooks_config)
      expect(config.webhooks).to eq(mock_webhooks_config)
    end
  end
end
