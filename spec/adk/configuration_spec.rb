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
    allow(ADK).to receive(:redis_options).and_return({ url: 'redis://localhost:6379' })
    allow(Redis).to receive(:new).and_return(redis_client)
    allow(ADK::DefinitionStore::RedisStore).to receive(:new).and_return(definition_store)
    allow(ADK::SessionService::Redis).to receive(:new).and_return(session_service)
    allow(ADK::Configuration::Webhooks).to receive(:new).and_return(webhooks_config)
  end

  describe '#initialize' do
    it 'sets defaults and initializes dependencies' do
      expect(ADK::DefinitionStore::RedisStore).to receive(:new).with(redis_client: redis_client)
      expect(ADK::SessionService::Redis).to receive(:new)

      expect(config.definition_store).to eq(definition_store)
      expect(config.session_service).to eq(session_service)
      expect(config.default_model_name).to eq('gemini-2.5-flash')
      expect(config.default_temperature).to eq(0.7)
      expect(config.webhooks).to eq(webhooks_config)
    end
  end
end
