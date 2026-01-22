# frozen_string_literal: true

require 'spec_helper'
require 'adk/configuration'

RSpec.describe ADK::Configuration do
  subject(:config) { described_class.new }

  let(:mock_redis) { instance_double(Redis) }
  let(:mock_store) { instance_double(ADK::DefinitionStore::RedisStore) }
  let(:mock_session) { instance_double(ADK::SessionService::Redis) }
  let(:mock_hooks) { instance_double(ADK::Configuration::Webhooks) }

  before do
    allow(Redis).to receive(:new).and_return(mock_redis)
    allow(ADK::DefinitionStore::RedisStore).to receive(:new).and_return(mock_store)
    allow(ADK::SessionService::Redis).to receive(:new).and_return(mock_session)
    allow(ADK::Configuration::Webhooks).to receive(:new).and_return(mock_hooks)
  end

  describe '#initialize' do
    it 'sets correct default values and initializes dependencies' do
      expect(ADK::DefinitionStore::RedisStore).to receive(:new).with(redis_client: mock_redis)
      expect(ADK::SessionService::Redis).to receive(:new)
      expect(ADK::Configuration::Webhooks).to receive(:new)

      expect(config.definition_store).to eq(mock_store)
      expect(config.session_service).to eq(mock_session)
      expect(config.webhooks).to eq(mock_hooks)
      expect(config.default_model_name).to eq('gemini-2.5-flash')
      expect(config.default_temperature).to eq(0.7)
    end
  end
end
