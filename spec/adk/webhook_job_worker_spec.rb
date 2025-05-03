# File: spec/adk/webhook_job_worker_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'sidekiq/testing'
require 'adk/webhook_job_worker'
require 'adk/agent'
require 'adk/session_service/redis'
require 'adk/errors'
require 'adk/event'
require 'adk/definition_store' # For DefinitionNotFound error

RSpec.describe ADK::WebhookJobWorker do
  # Use inline mode to execute job immediately
  before { Sidekiq::Testing.inline! }
  after { Sidekiq::Testing.disable! } # Disable after suite/context if needed

  let(:worker) { described_class.new }
  let(:agent_name) { :webhook_tester }
  let(:session_id) { 'sess_webhook_123' }
  let(:user_input) { { 'data' => 'input data' } }
  let(:redis_options) { { url: 'redis://localhost:6379/5' } }
  let(:session_service_config) { redis_options.merge(type: :redis) }

  let(:valid_payload) do
    {
      'agent_definition_name' => agent_name.to_s,
      'session_id' => session_id,
      'transformed_user_input' => user_input,
      'session_service_config' => session_service_config
    }
  end

  # Mocks
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:definition_store) { instance_double(ADK::DefinitionStore::RedisStore) }
  let(:definition) { instance_double(ADK::AgentDefinition, name: agent_name) }
  let(:session_service) { instance_double(ADK::SessionService::Redis) }
  let(:agent) { instance_double(ADK::Agent, name: agent_name) }
  let(:success_event) { ADK::Event.new(role: :agent, content: { status: :success, result: 'Task complete' }) }
  let(:error_event) { ADK::Event.new(role: :agent, content: { status: :error, error_message: 'Task failed' }) }

  before do
    # Stub global dependencies
    allow(ADK).to receive(:logger).and_return(logger)
    allow(ADK).to receive(:definition_store).and_return(definition_store)

    # Stub dependency instantiation
    # REMOVED allow(ADK::SessionService::Redis).to receive(:new).with(redis_options).and_return(session_service)
    # We will stub this only in specific tests where instantiation is expected to succeed.

    # Stub Agent.new using the :definition keyword arg (as per worker code)
    allow(ADK::Agent).to receive(:new).with(definition: definition).and_return(agent)

    # Default stubs for successful path
    allow(definition_store).to receive(:get_definition).with(agent_name).and_return(definition)
    allow(agent).to receive(:run_task)
      .with(session_id: session_id, user_input: user_input, session_service: session_service)
      .and_return(success_event)
  end

  describe '#perform' do
    context 'with a valid payload' do
      # REMOVED specific before block stubbing Redis.new
      # before do
      #  allow(ADK::SessionService::Redis).to receive(:new).with(redis_options).and_return(session_service)
      # end

      it 'instantiates Redis SessionService with correct options' do
        # Expect new to be called with the redis_client keyword arg
        expect(ADK::SessionService::Redis).to receive(:new) do |args|
          expect(args).to have_key(:redis_client)
          expect(args[:redis_client]).to be_a(Redis)
          # Optionally check client config: expect(args[:redis_client].config.options[:url]).to include('localhost:6379/5')
          session_service # Return the double
        end.at_least(:once) # Use at_least(:once) as other tests might also trigger it indirectly
        worker.perform(valid_payload)
      end

      it 'loads the correct agent definition' do
        # Need to allow Redis.new to succeed here for the test to proceed
        allow(ADK::SessionService::Redis).to receive(:new).and_return(session_service)
        expect(definition_store).to receive(:get_definition).with(agent_name).and_return(definition)
        worker.perform(valid_payload)
      end

      it 'instantiates the agent with the definition' do
        allow(ADK::SessionService::Redis).to receive(:new).and_return(session_service)
        expect(ADK::Agent).to receive(:new).with(definition: definition).and_return(agent)
        worker.perform(valid_payload)
      end

      it 'calls agent.run_task with correct arguments' do
        allow(ADK::SessionService::Redis).to receive(:new).and_return(session_service)
        expect(agent).to receive(:run_task)
          .with(session_id: session_id, user_input: user_input, session_service: session_service)
          .and_return(success_event)
        worker.perform(valid_payload)
      end

      it 'logs success when task completes successfully' do
        allow(ADK::SessionService::Redis).to receive(:new).and_return(session_service)
        allow(agent).to receive(:run_task).and_return(success_event)
        expect(logger).to receive(:info).with(/WebhookJobWorker starting job:/)
        expect(logger).to receive(:info).with(/WebhookJobWorker calling agent.run_task/)
        expect(logger).to receive(:info).with(/Agent task finished successfully/)
        worker.perform(valid_payload)
      end

      it 'logs error when task returns an error status' do
        allow(ADK::SessionService::Redis).to receive(:new).and_return(session_service)
        allow(agent).to receive(:run_task).and_return(error_event)
        expect(logger).to receive(:info).with(/WebhookJobWorker starting job:/)
        expect(logger).to receive(:info).with(/WebhookJobWorker calling agent.run_task/)
        expect(logger).to receive(:error).with(/Agent task finished with error/)
        worker.perform(valid_payload)
      end
    end

    context 'with an invalid payload' do
      it 'raises ArgumentError if agent_definition_name is missing' do
        invalid_payload = valid_payload.except('agent_definition_name')
        expect { worker.perform(invalid_payload) }.to raise_error(ArgumentError, /Invalid job payload/)
      end

      it 'raises ArgumentError if session_id is missing' do
        invalid_payload = valid_payload.except('session_id')
        expect { worker.perform(invalid_payload) }.to raise_error(ArgumentError, /Invalid job payload/)
      end
      # Add similar tests for user_input and session_service_config if desired
    end

    context 'when definition store fails' do
      it 're-raises DefinitionNotFound' do
        allow(definition_store).to receive(:get_definition).with(agent_name).and_raise(ADK::DefinitionStore::DefinitionNotFound)
        expect { worker.perform(valid_payload) }.to raise_error(ADK::DefinitionStore::DefinitionNotFound)
      end
    end

    context 'when session service instantiation fails' do
      it 'raises NotImplementedError for unsupported type' do
        invalid_config = { 'type' => 'unsupported' }
        payload = valid_payload.merge('session_service_config' => invalid_config)
        expect { worker.perform(payload) }.to raise_error(NotImplementedError, /Unsupported session service type/)
      end

      it 'propagates Redis connection errors' do
        # Expect Redis.new (called inside worker) to raise error
        expect(Redis).to receive(:new).with(url: 'redis://localhost:6379/5').and_raise(Redis::CannotConnectError) # Match **redis_opts_sym
        expect { worker.perform(valid_payload) }.to raise_error(Redis::CannotConnectError)
      end
    end

    context 'when agent instantiation fails' do
      it 'raises the error' do
        allow(ADK::Agent).to receive(:new).with(definition: definition).and_raise(StandardError, "Agent init boom")
        expect { worker.perform(valid_payload) }.to raise_error(StandardError, "Agent init boom")
      end
    end

    context 'when agent.run_task fails' do
      it 're-raises the error' do
        allow(agent).to receive(:run_task).and_raise(StandardError, "Task run boom")
        expect { worker.perform(valid_payload) }.to raise_error(StandardError, "Task run boom")
      end
    end
  end
end
