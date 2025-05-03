# File: spec/adk/web/webhook_integration_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sidekiq/testing'
require 'adk/web/webhook_listener'
require 'adk/web/app' # Main app for reference, though maybe not strictly needed for listener tests
require 'adk/agent'
require 'adk/webhook_job_worker' # Require the worker
require 'adk/definition_store'
require 'adk/configuration'
require 'adk/errors'
require 'adk/session_service/redis' # For mocking

RSpec.describe "Webhook Integration" do
  include Rack::Test::Methods

  # --- Configure Rack App Stack (similar to web_commands.rb) ---
  def app
    webhook_config = ADK.config.webhooks # Access mocked config
    listener_enabled = webhook_config.listener_enabled
    listener_base_path = webhook_config.base_path

    Rack::Builder.new do
      if listener_enabled
        ADK.logger.debug("Integration Spec: Mounting WebhookListener at #{listener_base_path}")
        map listener_base_path do
          run ADK::Web::WebhookListener.new
        end
      end
      # Mount main app if needed for other tests, otherwise optional here
      # run ADK::Web::App.new
    end.to_app
  end
  # -------------------------------------------------------------

  # --- Mocks and Test Data ---
  let(:webhook_config) { instance_double(ADK::Configuration::Webhooks) }
  let(:definition_store) { instance_double(ADK::DefinitionStore::RedisStore) }
  let(:agent_definition) { ADK::AgentDefinition.new } # Use a real definition object
  let(:session_service) { instance_double(ADK::SessionService::Redis) }
  let(:agent_instance) { instance_double(ADK::Agent, name: agent_name) }

  let(:agent_name) { :webhook_integration_agent }
  let(:base_path) { '/test-hooks' }
  let(:trigger_path) { "#{base_path}/agents/#{agent_name}/trigger" }
  let(:request_payload) { { 'event' => 'test_push', 'repo' => { 'id' => 987 } } }
  let(:request_json) { request_payload.to_json }
  let(:expected_session_id) { 'repo-session-987' }
  let(:expected_user_input) { 'Input from push event: test_push' }
  let(:expected_redis_opts) { { url: 'redis://mockhost:6379/1' } }

  # --- Test Setup ---
  before(:each) do
    # IMPORTANT: Use inline testing for immediate job execution
    Sidekiq::Testing.inline! 

    # Stub global ADK components
    allow(ADK).to receive(:config).and_return(instance_double(ADK::Configuration, webhooks: webhook_config))
    allow(ADK).to receive(:definition_store).and_return(definition_store)
    allow(ADK).to receive(:logger).and_return(instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil))
    allow(ADK).to receive(:redis_options).and_return(expected_redis_opts)

    # Configure webhook listener via mocked config
    allow(webhook_config).to receive(:listener_enabled).and_return(true)
    allow(webhook_config).to receive(:base_path).and_return(base_path)
    allow(webhook_config).to receive(:enable_dynamic_agent_handler).and_return(true)
    allow(webhook_config).to receive(:dynamic_agent_route_pattern).and_return('/agents/:agent_name/trigger')
    allow(webhook_config).to receive(:global_validator).and_return(nil)
    allow(webhook_config).to receive(:global_secret).and_return(nil)
    allow(webhook_config).to receive(:find_validator).and_return(nil) # No named validators for now
    allow(webhook_config).to receive(:static_routes).and_return({}) # Add stub for static routes
    
    # Configure the Agent Definition for webhook success
    # --- Capture outer scope 'agent_name' for use inside block ---
    current_agent_name = agent_name 
    # -----------------------------------------------------------
    agent_definition.define do |a|
      a.name current_agent_name # Use captured variable
      a.instruction 'Test Instruction'
      a.webhook_enabled true
      a.webhook_validator nil # No validation for base success case
      a.webhook_transformer ->(body) { "Input from push event: #{body['event']}" }
      a.webhook_session_extractor ->(body) { "repo-session-#{body.dig('repo', 'id')}" }
    end

    # Stub definition store to return our configured definition
    allow(definition_store).to receive(:get_definition).with(agent_name).and_return(agent_definition)
    
    # Stub Session Service instantiation (still needed)
    allow(ADK::SessionService::Redis).to receive(:new).with(expected_redis_opts).and_return(session_service)
    
    # Default stub for run_task - will be called on the *real* agent instance created by worker
    # We need to allow any instance of ADK::Agent to receive run_task
    allow_any_instance_of(ADK::Agent).to receive(:run_task)
      .with(session_id: expected_session_id, user_input: expected_user_input, session_service: session_service)
      .and_return(ADK::Event.new(role: :agent, content: { status: :success, result: 'Mock task ran' }))
  end

  after(:each) do
    Sidekiq::Testing.disable! # Clean up Sidekiq testing mode
  end

  # --- Test Cases ---

  context "POST #{'/agents/:agent_name/trigger'} (Dynamic Agent Route)" do
    it 'successfully receives webhook, processes job, and calls agent.run_task' do
      # Expectations for worker interactions
      expect(ADK::SessionService::Redis).to receive(:new).with(expected_redis_opts).and_return(session_service)
      expect(definition_store).to receive(:get_definition).with(agent_name).and_return(agent_definition)
      # We expect run_task to be called on *an* instance, not a specific stub
      expect_any_instance_of(ADK::Agent).to receive(:run_task)
        .with(session_id: expected_session_id, user_input: expected_user_input, session_service: session_service)
        .and_return(ADK::Event.new(role: :agent, content: { status: :success, result: 'Mock task ran' }))

      # Perform the HTTP request
      header 'Content-Type', 'application/json'
      post trigger_path, request_json

      # Verify listener response
      expect(last_response.status).to eq(202), "Expected status 202 but got #{last_response.status}. Body: #{last_response.body}"
      expect(last_response.content_type).to include('application/json')
      response_json = JSON.parse(last_response.body)
      expect(response_json['status']).to eq('accepted')
      expect(response_json['job_id']).not_to be_nil # Job ID is generated by Sidekiq
    end

    # Add more integration tests here for error paths if desired,
    # although many listener errors are covered by listener unit tests.
    # For example:
    context 'when agent definition is not webhook_enabled' do
       before do 
         # Reconfigure definition for this context
         # --- Capture outer scope 'agent_name' again ---
         current_agent_name_local = agent_name
         # -------------------------------------------
         agent_definition.define do |a| 
           a.name current_agent_name_local # Use captured variable
           a.instruction 'Test Instruction'
           a.webhook_enabled false # <<< Set to false for this context
           a.webhook_validator nil 
           a.webhook_transformer ->(body) { "Input from push event: #{body['event']}" }
           a.webhook_session_extractor ->(body) { "repo-session-#{body.dig('repo', 'id')}" }
         end
         # Ensure the store returns this modified definition
         allow(definition_store).to receive(:get_definition).with(agent_name).and_return(agent_definition)
       end
       
       it 'returns 404' do
         header 'Content-Type', 'application/json'
         post trigger_path, request_json
         expect(last_response.status).to eq(404)
         expect(last_response.body).to include('Webhook endpoint not found')
       end
    end
    
    # Example for validation failure (requires more setup for validator/secret)
    # context 'when validation fails' do ... end
  end
end 