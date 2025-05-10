# File: spec/adk/web/webhook_listener_error_handling_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'adk/web/webhook_listener'

RSpec.describe ADK::Web::WebhookListener do
  include Rack::Test::Methods

  # Set the app for Rack::Test
  def app
    ADK::Web::WebhookListener.new
  end

  # Shared variables for mocks
  let(:webhook_config) { instance_double(ADK::Configuration::Webhooks) }
  let(:definition_store) { instance_double(ADK::DefinitionStore::RedisStore) }
  let(:agent_definition) { instance_double(ADK::AgentDefinition) }
  let(:agent_name) { :test_error_agent }
  let(:trigger_path) { "/agents/#{agent_name}/trigger" }
  let(:request_payload) { { 'message' => 'Test webhook payload' } }
  let(:request_json) { request_payload.to_json }

  before(:each) do
    # Stub ADK.config
    allow(ADK).to receive(:config).and_return(
      instance_double(ADK::Configuration,
                      webhooks: webhook_config,
                      definition_store: definition_store)
    )

    # Suppress logging
    allow(ADK).to receive(:logger).and_return(
      instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil)
    )

    # Default webhook config stubs
    allow(webhook_config).to receive(:enable_dynamic_agent_handler).and_return(true)
    allow(webhook_config).to receive(:dynamic_agent_route_pattern).and_return('/agents/:agent_name/trigger')
    allow(webhook_config).to receive(:global_validator).and_return(nil)
    allow(webhook_config).to receive(:global_secret).and_return(nil)
    allow(webhook_config).to receive(:find_validator).and_return(nil)
    allow(webhook_config).to receive(:static_routes).and_return({})

    # Setup registry and store to find agent definition
    allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(agent_definition)
    allow(definition_store).to receive(:get_definition).with(agent_name).and_return({ webhook_enabled: true,
                                                                                      webhook_secret: nil })

    # Default agent definition stubs
    allow(agent_definition).to receive(:webhook_enabled).and_return(true)
    allow(agent_definition).to receive(:webhook_secret).and_return(nil)
    allow(agent_definition).to receive(:webhook_validator).and_return(nil)
  end

  describe 'Error Handling Cases' do
    context 'when JSON request body is malformed' do
      it 'returns 400 Bad Request for invalid JSON' do
        header 'Content-Type', 'application/json'
        post trigger_path, 'this is not valid JSON:'

        expect(last_response.status).to eq(400)
        expect(JSON.parse(last_response.body)['error_message']).to include('Invalid JSON format')
      end
    end

    context 'with global validator' do
      let(:global_validator) { ->(req, secret) { req.env['HTTP_X_GLOBAL_TOKEN'] == 'correct-token' } }

      before do
        allow(webhook_config).to receive(:global_validator).and_return(global_validator)
      end

      it 'accepts requests that pass global validation' do
        header 'Content-Type', 'application/json'
        header 'X-Global-Token', 'correct-token'

        # We'll need to mock the rest of the flow for this test
        allow(agent_definition).to receive(:webhook_transformer).and_return(->(payload) { payload })
        allow(agent_definition).to receive(:webhook_session_extractor).and_return(->(payload) { 'test-session-id' })
        allow(Sidekiq::Client).to receive(:push).and_return('job-123')

        post trigger_path, request_json

        expect(last_response.status).to eq(202)
      end

      it 'rejects requests that fail global validation' do
        header 'Content-Type', 'application/json'
        header 'X-Global-Token', 'wrong-token'

        post trigger_path, request_json

        expect(last_response.status).to eq(401)
        expect(JSON.parse(last_response.body)['error_message']).to include('Unauthorized')
      end
    end

    context 'with per-agent validator' do
      let(:agent_validator) { ->(req, secret) { req.env['HTTP_X_AGENT_TOKEN'] == 'agent-token' } }

      before do
        allow(agent_definition).to receive(:webhook_validator).and_return(agent_validator)
        allow(agent_definition).to receive(:webhook_secret).and_return('agent-secret')

        # Need to mock these for successful validation path
        allow(agent_definition).to receive(:webhook_transformer).and_return(->(payload) { payload })
        allow(agent_definition).to receive(:webhook_session_extractor).and_return(->(payload) { 'test-session-id' })
        allow(Sidekiq::Client).to receive(:push).and_return('job-123')
      end

      it 'accepts requests that pass agent-specific validation' do
        header 'Content-Type', 'application/json'
        header 'X-Agent-Token', 'agent-token'

        post trigger_path, request_json

        expect(last_response.status).to eq(202)
      end

      it 'rejects requests that fail agent-specific validation' do
        header 'Content-Type', 'application/json'
        header 'X-Agent-Token', 'wrong-token'

        post trigger_path, request_json

        expect(last_response.status).to eq(401)
        expect(JSON.parse(last_response.body)['error_message']).to include('Unauthorized')
      end
    end

    context 'when validator raises an unexpected error' do
      let(:error_validator) { ->(req, secret) { raise StandardError, 'Unexpected validator error' } }

      before do
        allow(agent_definition).to receive(:webhook_validator).and_return(error_validator)
      end

      it 'returns 500 Internal Server Error' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json

        expect(last_response.status).to eq(500)
        expect(JSON.parse(last_response.body)['error_message']).to include('Internal Server Error during validation')
      end
    end
  end
end
