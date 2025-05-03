# File: spec/adk/web/webhook_listener_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sidekiq/testing' # To mock Sidekiq queue
require 'adk/web/webhook_listener'
require 'adk/agent' # For AgentDefinition stubbing
require 'adk/definition_store' # For stubbing
require 'adk/configuration' # For stubbing
require 'adk/errors'

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
  let(:request_payload) { { 'data' => 'some_value', 'repo_id' => 'repo-123' } }
  let(:request_json) { request_payload.to_json }
  let(:agent_name) { :test_webhook_agent }
  let(:trigger_path) { "/agents/#{agent_name}/trigger" }
  let(:transformer_proc) { ->(payload) { "Transformed: #{payload['data']}" } }
  let(:extractor_proc) { ->(payload) { "session-#{payload['repo_id']}" } }
  let(:validator_proc) { ->(req, secret) { true } }
  # Redis options used by the webhook listener
  let(:redis_options) { { url: 'redis://mockhost:6379/1' } }

  # Reset Sidekiq testing mode before each example
  before(:each) do
    Sidekiq::Testing.fake! # Use fake queue for testing pushes
    Sidekiq::Worker.clear_all # Clear jobs between tests

    # Stub global ADK config and store
    allow(ADK).to receive(:config).and_return(instance_double(ADK::Configuration, webhooks: webhook_config))
    allow(ADK).to receive(:definition_store).and_return(definition_store)
    allow(ADK).to receive(:logger).and_return(instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil)) # Suppress logging

    # Stub ADK.redis_options which is used by WebhookListener to build the session_service_config
    allow(ADK).to receive(:redis_options).and_return(redis_options)

    # Default stubs for a successful path
    allow(webhook_config).to receive(:enable_dynamic_agent_handler).and_return(true)
    allow(webhook_config).to receive(:dynamic_agent_route_pattern).and_return('/agents/:agent_name/trigger')
    allow(definition_store).to receive(:get_definition).with(agent_name).and_return(agent_definition)
    allow(agent_definition).to receive(:webhook_enabled).and_return(true)
    allow(agent_definition).to receive(:webhook_validator).and_return(nil) # No validator by default
    allow(agent_definition).to receive(:webhook_secret).and_return(nil)
    allow(agent_definition).to receive(:webhook_transformer).and_return(transformer_proc)
    allow(agent_definition).to receive(:webhook_session_extractor).and_return(extractor_proc)
    allow(webhook_config).to receive(:global_validator).and_return(nil)
    allow(webhook_config).to receive(:global_secret).and_return(nil)
    allow(webhook_config).to receive(:find_validator).and_return(nil) # No named validators for now
    allow(webhook_config).to receive(:static_routes).and_return({}) # Add stub for static routes
  end

  describe 'POST /agents/:agent_name/trigger' do
    context 'when request is valid and agent is configured correctly' do
      it 'enqueues a job to Sidekiq' do
        expect(Sidekiq::Client).to receive(:push) do |job|
          expect(job['queue']).to eq('adk_webhooks')
          expect(job['class']).to eq('ADK::WebhookJobWorker')
          expect(job['args'][0]['agent_definition_name']).to eq(agent_name.to_s)
          expect(job['args'][0]['session_id']).to eq('session-repo-123')
          expect(job['args'][0]['transformed_user_input']).to eq('Transformed: some_value')
          # Update expectation to match the actual format used by WebhookListener
          # The webhook listener stringifies all keys and adds 'type' => 'redis'
          expect(job['args'][0]['session_service_config']).to eq({ 'url' => 'redis://mockhost:6379/1',
                                                                   'type' => 'redis' })
          'fake_job_id' # Return a fake JID
        end

        header 'Content-Type', 'application/json'
        post trigger_path, request_json

        expect(last_response.status).to eq(202)
      end

      it 'returns status 202 Accepted with job ID' do
        allow(Sidekiq::Client).to receive(:push).and_return('test_job_id_123') # Stub push to return a JID
        header 'Content-Type', 'application/json'
        post trigger_path, request_json

        expect(last_response.status).to eq(202)
        expect(last_response.content_type).to include('application/json')
        response_json = JSON.parse(last_response.body)
        expect(response_json['status']).to eq('accepted')
        expect(response_json['job_id']).to eq('test_job_id_123')
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
        allow(definition_store).to receive(:get_definition).with(agent_name).and_raise(
          ADK::DefinitionStore::DefinitionNotFound, "not found"
        )
      }

      it 'returns status 404 Not Found' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(404)
        expect(last_response.body).to include('Agent definition not found')
      end
    end

    context 'when agent is not webhook_enabled' do
      before { allow(agent_definition).to receive(:webhook_enabled).and_return(false) }

      it 'returns status 404 Not Found' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(404)
        expect(last_response.body).to include('Webhook endpoint not found') # Matches 404 message for disabled
      end
    end

    context 'when validation fails' do
      before do
        allow(agent_definition).to receive(:webhook_validator).and_return(validator_proc)
        allow(validator_proc).to receive(:call).and_return(false) # Make validator fail
      end

      it 'returns status 401 Unauthorized' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(401)
        expect(last_response.body).to include('Unauthorized')
      end
    end

    context 'when transformation fails' do
      let(:transformer_proc) { ->(payload) { raise StandardError, "Transform boom!" } }
      before { allow(agent_definition).to receive(:webhook_transformer).and_return(transformer_proc) }

      it 'returns status 500 Internal Server Error' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(500)
        expect(last_response.body).to include('Internal Server Error during payload transformation')
      end
    end

    context 'when transformation raises WebhookConfigurationError' do
      let(:transformer_proc) { ->(payload) { raise ADK::WebhookConfigurationError, "Bad payload for transform" } }
      before { allow(agent_definition).to receive(:webhook_transformer).and_return(transformer_proc) }

      it 'returns status 400 Bad Request' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Configuration Error: Bad payload for transform')
      end
    end

    context 'when session extraction fails' do
      let(:extractor_proc) { ->(payload) { raise StandardError, "Extract boom!" } }
      before { allow(agent_definition).to receive(:webhook_session_extractor).and_return(extractor_proc) }

      it 'returns status 500 Internal Server Error' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(500)
        expect(last_response.body).to include('Internal Server Error during session ID extraction')
      end
    end

    context 'when session extraction raises WebhookConfigurationError' do
      let(:extractor_proc) { ->(payload) { raise ADK::WebhookConfigurationError, "Missing ID for session" } }
      before { allow(agent_definition).to receive(:webhook_session_extractor).and_return(extractor_proc) }

      it 'returns status 400 Bad Request' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Configuration Error: Missing ID for session')
      end
    end

    context 'when enqueuing fails' do
      before { allow(Sidekiq::Client).to receive(:push).and_raise(Redis::CannotConnectError, "Queue down") }

      it 'returns status 503 Service Unavailable' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(503)
        expect(last_response.body).to include('Error connecting to job queue')
      end
    end

    context 'when Sidekiq push returns nil' do
      before { allow(Sidekiq::Client).to receive(:push).and_return(nil) }

      it 'returns status 503 Service Unavailable' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_json
        expect(last_response.status).to eq(503)
        expect(last_response.body).to include('Failed to queue background job')
      end
    end

    # TODO: Add tests for global validators/secrets if needed
    # TODO: Add tests for static route handling (once implemented)
  end
end
