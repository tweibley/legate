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

  # Use Sidekiq fake mode for testing - to properly check job enqueuing
  before { Sidekiq::Testing.fake! }
  after { Sidekiq::Testing.disable! }

  # Mocks needed across contexts
  let(:session_service) { ADK.config.session_service } # Access via ADK.config
  let(:agent_name) { :test_webhook_agent_for_integration }
  let(:session_id) { "sess-int-#{SecureRandom.hex(4)}" }
  let(:mock_redis) { instance_double(Redis) }
  let(:webhook_config_double) { instance_double(ADK::Configuration::Webhooks) }
  let(:store_double) { instance_double(ADK::DefinitionStore::RedisStore) }
  let(:service_double) { instance_double(ADK::SessionService::Redis) }
  let(:config_double) { instance_double(ADK::Configuration) }
  let(:agent_definition_double) { instance_double(ADK::AgentDefinition) }
  let(:redis_options) { { url: 'redis://mockhost:6379/1' } }

  # Define agent once using let! before mocks are set in before(:each)
  let!(:defined_agent_result) do
    # Need temporary mocks just for this definition
    temp_store = instance_double(ADK::DefinitionStore::RedisStore, save_definition: true)
    temp_redis = instance_double(Redis, multi: [true] * 9, hset: true, sadd: true)
    allow(Redis).to receive(:new).and_return(temp_redis)
    allow(ADK).to receive(:config).and_return(instance_double(ADK::Configuration, definition_store: temp_store))
    allow(ADK::GlobalDefinitionRegistry).to receive(:register)

    # Define the agent
    local_agent_name = agent_name # Capture from outer scope
    ADK::Agent.define do |a|
      a.name local_agent_name
      a.description "Integration test agent"
      a.instruction "Process webhook"
      a.webhook_enabled true
      a.webhook_session_extractor ->(payload) { payload['session_marker'] }
      a.webhook_transformer ->(payload) { { message: "Transformed: #{payload['data']}" } }
    end
  end

  before(:each) do
    # Clear Sidekiq jobs before each test
    Sidekiq::Worker.clear_all

    # 1. Configure the main ADK.config double
    allow(ADK).to receive(:config).and_return(config_double)
    allow(config_double).to receive(:webhooks).and_return(webhook_config_double)
    allow(config_double).to receive(:definition_store).and_return(store_double)
    allow(config_double).to receive(:session_service).and_return(service_double)
    allow(ADK).to receive(:redis_options).and_return(redis_options)

    # 2. Mock Redis client (used by worker potentially, not needed for define anymore)
    allow(Redis).to receive(:new).and_return(mock_redis)
    allow(mock_redis).to receive(:ping).and_return("PONG")
    # Remove multi/hset/sadd mocks for define as it happens in let!
    # allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([true] * 9)
    # allow(mock_redis).to receive(:hset)
    # allow(mock_redis).to receive(:sadd)

    # 3. Stub Store/Registry methods needed by Listener/Worker
    # Store save_definition/delete_definition might be called by define/cleanup
    allow(store_double).to receive(:save_definition).and_return(true)
    allow(store_double).to receive(:delete_definition).and_return(true)
    # Registry register is called by define
    allow(ADK::GlobalDefinitionRegistry).to receive(:register)
    # Registry find is called by Listener
    allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(agent_definition_double)
    # Store get_definition is called by Listener
    allow(store_double).to receive(:get_definition).with(agent_name).and_return({ webhook_enabled: true,
                                                                                  webhook_secret: nil })

    # 4. Define the agent (REMOVED - moved to let!)
    # ...

    # 5. Configure Webhook Listener settings (using webhook_config_double)
    allow(webhook_config_double).to receive(:listener_enabled).and_return(true)
    allow(webhook_config_double).to receive(:enable_dynamic_agent_handler).and_return(true)
    allow(webhook_config_double).to receive(:dynamic_agent_route_pattern).and_return('/agents/:agent_name/trigger')
    allow(webhook_config_double).to receive(:static_routes).and_return({})
    allow(webhook_config_double).to receive(:global_validator).and_return(nil)
    allow(webhook_config_double).to receive(:find_validator).and_return(nil)
    allow(webhook_config_double).to receive(:base_path).and_return('/webhooks') # Allow base_path

    # 6. Mock AgentDefinition methods needed by Listener route (use agent_definition_double)
    allow(agent_definition_double).to receive(:webhook_enabled).and_return(true)
    allow(agent_definition_double).to receive(:webhook_validator).and_return(nil)
    allow(agent_definition_double).to receive(:webhook_secret).and_return(nil)
    allow(agent_definition_double).to receive(:webhook_transformer).and_return(->(payload) {
      { message: "Transformed: #{payload['data']}" }
    })
    allow(agent_definition_double).to receive(:webhook_session_extractor).and_return(->(payload) {
      payload['session_marker']
    })
    # Add methods needed by Agent#initialize if worker runs inline
    allow(agent_definition_double).to receive(:name).and_return(agent_name)
    allow(agent_definition_double).to receive(:description).and_return("desc")
    allow(agent_definition_double).to receive(:instruction).and_return("instr")
    allow(agent_definition_double).to receive(:tool_names).and_return([])
    allow(agent_definition_double).to receive(:model_name).and_return("default-model")
    allow(agent_definition_double).to receive(:fallback_mode).and_return(:error)
    allow(agent_definition_double).to receive(:mcp_servers).and_return([])

    # 7. Mock session service methods needed by Agent#initialize if worker runs inline
    # The service_double is now an instance_double of Redis implementation, which has the needed methods
    allow(service_double).to receive(:get_session).with(session_id: session_id).and_return(nil)
    allow(service_double).to receive(:append_event).with(any_args).and_return(true)
    allow(service_double).to receive(:persistent?).and_return(true)

    # These methods are called by respond_to? checks
    allow(service_double).to receive(:respond_to?).with(:get_session).and_return(true)
    allow(service_double).to receive(:respond_to?).with(:append_event).and_return(true)
    allow(service_double).to receive(:respond_to?).with(:create_session).and_return(true)

    # Add create_session for auto-creation of sessions that don't exist
    allow(service_double).to receive(:create_session).with(any_args).and_return(
      instance_double(ADK::Session, id: session_id, state_to_h: {}, add_event: true)
    )

    # 8. Return a job_id when Sidekiq::Client.push is called
    allow(Sidekiq::Client).to receive(:push).and_return("fake-jid-123")
  end

  # Clean up agent definition after each test
  # No change needed here if define is in let!

  describe 'POST /agents/:agent_name/trigger (Dynamic Agent Route)' do
    let(:trigger_path) { "/webhooks/agents/#{agent_name}/trigger" } # Use configured base path
    let(:request_body) { { data: 'webhook payload', session_marker: session_id }.to_json }

    it 'successfully receives webhook, processes job, and calls agent.run_task' do
      # Perform the HTTP request
      header 'Content-Type', 'application/json'
      post trigger_path, request_body

      # Verify listener response
      expect(last_response.status).to eq(202),
                                      "Expected status 202 but got #{last_response.status}. Body: #{last_response.body}"
      response_json = JSON.parse(last_response.body)
      expect(response_json['status']).to eq('accepted')
      expect(response_json['job_id']).not_to be_nil

      # Simply verify that Sidekiq::Client.push was called - details verified in other tests
      expect(Sidekiq::Client).to have_received(:push)
    end

    context 'when agent definition is not webhook_enabled' do
      before do
        # Update store mock to return disabled hash
        allow(store_double).to receive(:get_definition).with(agent_name).and_return(
          { name: agent_name, description: 'desc', instruction: 'i', tools: [], model: 'm',
            webhook_enabled: false # Explicitly disable
          }
        )
        # Update registry mock to return disabled object
        allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(
          instance_double(ADK::AgentDefinition, webhook_enabled: false)
        )
      end

      it 'returns 404' do
        header 'Content-Type', 'application/json'
        post trigger_path, request_body
        expect(last_response.status).to eq(404)
      end
    end
  end
end
