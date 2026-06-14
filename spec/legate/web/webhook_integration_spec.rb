# File: spec/legate/web/webhook_integration_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'legate/web/webhook_listener'
require 'legate/web/app' # Main app for reference
require 'legate/agent'
require 'legate/configuration'
require 'legate/errors'

RSpec.describe 'Webhook Integration' do
  include Rack::Test::Methods

  # --- Configure Rack App Stack (similar to web_commands.rb) ---
  def app
    webhook_config = Legate.config.webhooks
    listener_enabled = webhook_config.listener_enabled
    listener_base_path = webhook_config.base_path

    Rack::Builder.new do
      if listener_enabled
        Legate.logger.debug("Integration Spec: Mounting WebhookListener at #{listener_base_path}")
        map listener_base_path do
          run Legate::Web::WebhookListener.new
        end
      end
    end.to_app
  end
  # -------------------------------------------------------------

  # Mocks needed across contexts
  let(:session_service) { Legate::SessionService::InMemory.new }
  let(:agent_name) { :test_webhook_agent_for_integration }
  let(:session_id) { "sess-int-#{SecureRandom.hex(4)}" }
  let(:webhook_config_double) { instance_double(Legate::Configuration::Webhooks) }
  let(:config_double) { instance_double(Legate::Configuration) }
  let(:agent_definition_double) { instance_double(Legate::AgentDefinition) }

  # Define agent once using let! before mocks are set in before(:each)
  let!(:defined_agent_result) do
    allow(Legate::GlobalDefinitionRegistry).to receive(:register)

    # Define the agent
    local_agent_name = agent_name
    Legate::Agent.define do |a|
      a.name local_agent_name
      a.description 'Integration test agent'
      a.instruction 'Process webhook'
      a.webhook_enabled true
      a.webhook_session_extractor ->(payload) { payload['session_marker'] }
      a.webhook_transformer ->(payload) { { message: "Transformed: #{payload['data']}" } }
    end
  end

  before(:each) do
    # 1. Configure the main Legate.config double
    allow(Legate).to receive(:config).and_return(config_double)
    allow(config_double).to receive(:webhooks).and_return(webhook_config_double)
    allow(config_double).to receive(:session_service).and_return(session_service)

    # 2. Stub Registry methods needed by Listener
    allow(Legate::GlobalDefinitionRegistry).to receive(:register)
    allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(agent_definition_double)
    allow(Legate::GlobalDefinitionRegistry).to receive(:all).and_return({ agent_name => agent_definition_double })

    # 3. Configure Webhook Listener settings
    allow(webhook_config_double).to receive(:listener_enabled).and_return(true)
    allow(webhook_config_double).to receive(:enable_dynamic_agent_handler).and_return(true)
    allow(webhook_config_double).to receive(:dynamic_agent_route_pattern).and_return('/agents/:agent_name/trigger')
    allow(webhook_config_double).to receive(:static_routes).and_return({})
    allow(webhook_config_double).to receive(:global_validator).and_return(nil)
    allow(webhook_config_double).to receive(:global_secret).and_return(nil)
    allow(webhook_config_double).to receive(:find_validator).and_return(nil)
    allow(webhook_config_double).to receive(:base_path).and_return('/webhooks')

    # 4. Mock AgentDefinition methods needed by Listener route
    allow(agent_definition_double).to receive(:webhook_enabled).and_return(true)
    allow(agent_definition_double).to receive(:webhook_validator).and_return(nil)
    allow(agent_definition_double).to receive(:webhook_secret).and_return(nil)
    allow(agent_definition_double).to receive(:webhook_transformer).and_return(->(payload) {
      { message: "Transformed: #{payload['data']}" }
    })
    allow(agent_definition_double).to receive(:webhook_session_extractor).and_return(->(payload) {
      payload['session_marker']
    })
    allow(agent_definition_double).to receive(:name).and_return(agent_name)
    allow(agent_definition_double).to receive(:description).and_return('desc')
    allow(agent_definition_double).to receive(:instruction).and_return('instr')
    allow(agent_definition_double).to receive(:tool_names).and_return([])
    allow(agent_definition_double).to receive(:model_name).and_return('default-model')
    allow(agent_definition_double).to receive(:fallback_mode).and_return(:error)
    allow(agent_definition_double).to receive(:mcp_servers).and_return([])

    # 5. Stub session service methods used by webhook listener
    allow(session_service).to receive(:get_session).and_return(nil)
    allow(session_service).to receive(:create_session).and_return(
      instance_double(Legate::Session, id: session_id, state_to_h: {}, add_event: true)
    )

    # 6. Stub Concurrent::Promises.future to prevent actual thread spawning
    allow(Concurrent::Promises).to receive(:future).and_return(double('future'))
  end

  describe 'POST /agents/:agent_name/trigger (Dynamic Agent Route)' do
    let(:trigger_path) { "/webhooks/agents/#{agent_name}/trigger" }
    let(:request_body) { { data: 'webhook payload', session_marker: session_id }.to_json }

    it 'successfully receives webhook and returns 202 Accepted with task_id' do
      header 'Content-Type', 'application/json'
      post trigger_path, request_body

      expect(last_response.status).to eq(202),
                                      "Expected status 202 but got #{last_response.status}. Body: #{last_response.body}"
      response_json = JSON.parse(last_response.body)
      expect(response_json['status']).to eq('accepted')
      expect(response_json['task_id']).not_to be_nil
    end

    context 'when agent definition is not webhook_enabled' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(
          instance_double(Legate::AgentDefinition, webhook_enabled: false)
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
