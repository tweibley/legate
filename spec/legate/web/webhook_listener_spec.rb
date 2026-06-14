# File: spec/legate/web/webhook_listener_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'legate/web/webhook_listener'
require 'legate/agent' # For AgentDefinition stubbing
require 'legate/configuration' # For stubbing
require 'legate/errors'

RSpec.describe Legate::Web::WebhookListener do
  include Rack::Test::Methods

  # Set the app for Rack::Test
  def app
    Legate::Web::WebhookListener.new
  end

  # Shared variables for mocks
  let(:webhook_config) { instance_double(Legate::Configuration::Webhooks) }
  let(:session_service) { Legate::SessionService::InMemory.new }
  let(:agent_definition) { instance_double(Legate::AgentDefinition) }
  let(:request_payload) { { 'data' => 'some_value', 'repo_id' => 'repo-123' } }
  let(:request_json) { request_payload.to_json }
  let(:agent_name) { :test_webhook_agent }
  let(:trigger_path) { "/agents/#{agent_name}/trigger" }
  let(:transformer_proc) { ->(payload) { "Transformed: #{payload['data']}" } }
  let(:extractor_proc) { ->(payload) { "session-#{payload['repo_id']}" } }
  let(:validator_proc) { ->(req, secret) { true } }

  before(:each) do
    # Stub global Legate config
    allow(Legate).to receive(:config).and_return(instance_double(Legate::Configuration, webhooks: webhook_config,
                                                                                        session_service: session_service))
    # Stub GlobalDefinitionRegistry to find our mock definition
    allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(agent_definition)
    allow(Legate::GlobalDefinitionRegistry).to receive(:all).and_return({ agent_name => agent_definition })

    allow(Legate).to receive(:logger).and_return(instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil)) # Suppress logging

    # Default stubs for webhook config
    allow(webhook_config).to receive(:enable_dynamic_agent_handler).and_return(true)
    allow(webhook_config).to receive(:dynamic_agent_route_pattern).and_return('/agents/:agent_name/trigger')
    allow(webhook_config).to receive(:global_validator).and_return(nil)
    allow(webhook_config).to receive(:global_secret).and_return(nil)
    allow(webhook_config).to receive(:find_validator).and_return(nil)
    allow(webhook_config).to receive(:static_routes).and_return({})

    # Default stubs for agent_definition instance double (found via registry)
    allow(agent_definition).to receive(:webhook_enabled).and_return(true)
    allow(agent_definition).to receive(:webhook_validator).and_return(nil)
    allow(agent_definition).to receive(:webhook_secret).and_return(nil)
    allow(agent_definition).to receive(:webhook_transformer).and_return(transformer_proc)
    allow(agent_definition).to receive(:webhook_session_extractor).and_return(extractor_proc)

    # Stub session service methods used by the listener
    allow(session_service).to receive(:get_session).and_return(nil)
    allow(session_service).to receive(:create_session).and_return(instance_double(Legate::Session, id: 'session-repo-123'))

    # Stub Concurrent::Promises.future to prevent actual thread spawning in tests
    allow(Concurrent::Promises).to receive(:future).and_return(double('future'))
  end

  describe 'POST /agents/:agent_name/trigger' do
    context 'when request is valid and agent is configured correctly' do
      it 'spawns a background task and returns 202' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json

        expect(last_response.status).to eq(202)
      end

      it 'returns status 202 Accepted with task_id' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json

        expect(last_response.status).to eq(202)
        expect(last_response.content_type).to include('application/json')
        response_json = JSON.parse(last_response.body)
        expect(response_json['status']).to eq('accepted')
        expect(response_json['task_id']).not_to be_nil
        expect(response_json['message']).to include(agent_name.to_s)
      end
    end

    context 'when dynamic handler is disabled' do
      before { allow(webhook_config).to receive(:enable_dynamic_agent_handler).and_return(false) }

      it 'returns status 403 Forbidden' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(403)
        expect(last_response.body).to include('Dynamic agent webhooks are disabled')
      end
    end

    context 'when agent definition is not found' do
      before {
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(nil)
      }

      it 'returns status 500 Internal Server Error' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(500)
        expect(last_response.body).to include('Agent definition not loaded')
      end
    end

    context 'when agent is not webhook_enabled' do
      before {
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(agent_definition)
        allow(agent_definition).to receive(:webhook_enabled).and_return(false)
      }

      it 'returns status 404 Not Found' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(404)
        expect(last_response.body).to include('Webhook endpoint not found')
      end
    end

    context 'when validation fails' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(agent_definition)
        allow(agent_definition).to receive(:webhook_validator).and_return(validator_proc)
        allow(agent_definition).to receive(:webhook_secret).and_return(nil)
        allow(validator_proc).to receive(:call).and_return(false)
      end

      it 'returns status 401 Unauthorized' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(401)
        expect(last_response.body).to include('Unauthorized')
      end
    end

    context 'when transformation fails' do
      let(:transformer_proc) { ->(payload) { raise StandardError, 'Transform boom!' } }
      before { allow(agent_definition).to receive(:webhook_transformer).and_return(transformer_proc) }

      it 'returns status 500 Internal Server Error' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(500)
        expect(last_response.body).to include('Internal Server Error during payload transformation')
      end
    end

    context 'when transformation raises WebhookConfigurationError' do
      let(:transformer_proc) { ->(payload) { raise Legate::WebhookConfigurationError, 'Bad payload for transform' } }
      before { allow(agent_definition).to receive(:webhook_transformer).and_return(transformer_proc) }

      it 'returns status 400 Bad Request' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Configuration Error: Bad payload for transform')
      end
    end

    context 'when session extraction fails' do
      let(:extractor_proc) { ->(payload) { raise StandardError, 'Extract boom!' } }
      before { allow(agent_definition).to receive(:webhook_session_extractor).and_return(extractor_proc) }

      it 'returns status 500 Internal Server Error' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(500)
        expect(last_response.body).to include('Internal Server Error during session ID extraction')
      end
    end

    context 'when session extraction raises WebhookConfigurationError' do
      let(:extractor_proc) { ->(payload) { raise Legate::WebhookConfigurationError, 'Missing ID for session' } }
      before { allow(agent_definition).to receive(:webhook_session_extractor).and_return(extractor_proc) }

      it 'returns status 400 Bad Request' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Configuration Error: Missing ID for session')
      end
    end

    context 'with global validator' do
      let(:global_validator_proc) { ->(_req, _secret) { true } }

      before do
        allow(webhook_config).to receive(:global_validator).and_return(global_validator_proc)
        allow(webhook_config).to receive(:global_secret).and_return('global_secret')
        allow(agent_definition).to receive(:webhook_validator).and_return(nil)
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(agent_definition)
      end

      it 'uses global validator when agent validator is not set' do
        expect(global_validator_proc).to receive(:call).with(anything, 'global_secret').and_return(true)

        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(202)
      end

      it 'rejects request if global validator fails' do
        allow(global_validator_proc).to receive(:call).and_return(false)

        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(401)
      end
    end
  end

  describe 'Static Routes' do
    let(:static_handler) { ->(_req) { [200, { 'Content-Type' => 'text/plain' }, ['Static OK']] } }
    let(:static_route_config) { instance_double(Legate::Configuration::Webhooks::RouteConfig, handler: static_handler, validator: nil, secret: nil) }

    before do
      allow(webhook_config).to receive(:static_routes).and_return({
                                                                    'GET /static_test' => static_route_config
                                                                  })
    end

    it 'handles registered static route' do
      get '/static_test'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq('Static OK')
    end

    context 'with validation' do
      let(:path) { '/validated_static_pass' }
      let(:static_validator) { ->(_req, _secret) { true } }
      let(:validated_route_config) {
        instance_double(Legate::Configuration::Webhooks::RouteConfig,
                        handler: static_handler,
                        validator: static_validator,
                        secret: 'static_secret')
      }

      before do
        allow(webhook_config).to receive(:static_routes).and_return({
                                                                      "POST #{path}" => validated_route_config
                                                                    })
      end

      it 'passes validation' do
        expect(static_validator).to receive(:call).with(anything, 'static_secret').and_call_original
        post path
        expect(last_response.status).to eq(200)
      end

      context 'when validator returns false' do
        let(:path) { '/validated_static_fail' }
        let(:static_validator) { ->(_req, _secret) { false } }

        it 'fails validation' do
          post path
          expect(last_response.status).to eq(401)
        end
      end
    end
  end
end
