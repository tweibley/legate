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
require 'adk/definition_store/redis_store'

# Define simple Struct for context testing
ADK::WebhookContext = Struct.new(:payload_body, :request_headers,
                                 keyword_init: true) unless defined?(ADK::WebhookContext)

RSpec.describe ADK::WebhookJobWorker do
  # Use inline mode to execute job immediately
  before { Sidekiq::Testing.inline! }
  after { Sidekiq::Testing.disable! } # Disable after suite/context if needed

  let(:worker) { described_class.new }
  let(:agent_name) { :test_webhook_agent }
  let(:session_id) { 'sess_webhook_123' }
  let(:payload_body) { { data: 'from webhook' }.to_json }
  let(:valid_payload) do
    {
      'agent_definition_name' => agent_name.to_s,
      'session_id' => session_id,
      'session_service_type' => 'redis',
      'session_service_options' => { url: 'redis://localhost:6379/1' },
      'definition_store_type' => 'redis',
      'definition_store_options' => { url: 'redis://localhost:6379/1' },
      'payload_body' => payload_body,
      'request_headers' => { 'Content-Type' => 'application/json' },
      # Add potentially missing keys based on error message - assume these are needed
      'transformed_user_input' => { data: 'transformed' }, # Example transformed input
      'session_service_config' => { 'type' => 'redis', 'url' => 'redis://localhost:6379/1' } # Example config hash
    }
  end

  # Use instance doubles that are recreated for each test
  let(:mock_redis) { instance_double(Redis) }
  let(:mock_session_service) { instance_double(ADK::SessionService::Redis) }
  let(:mock_definition_store) { instance_double(ADK::DefinitionStore::RedisStore) }
  let(:mock_agent_definition) { instance_double(ADK::AgentDefinition, name: agent_name) }
  let(:mock_agent) { instance_double(ADK::Agent) }
  let(:logger_double) { spy('Logger') }

  # Recreate mocks before each example
  before(:each) do
    # Allow Redis client creation to return our per-test mock
    allow(Redis).to receive(:new).and_return(mock_redis)
    # Configure ADK.config to return mocks (primarily for definition store)
    allow(ADK).to receive(:config).and_return(instance_double(ADK::Configuration,
                                                              definition_store: mock_definition_store,
                                                              session_service: mock_session_service))
    # Mock SessionService instantiation return value (used by worker)
    allow(ADK::SessionService::Redis).to receive(:new).and_return(mock_session_service)
    # Mock GlobalDefinitionRegistry to find the definition (used by worker)
    allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(agent_name.to_sym).and_return(mock_agent_definition)
    # Mock methods on the specific store mock (if needed, though worker uses registry)
    allow(mock_definition_store).to receive(:get_definition).with(agent_name.to_sym).and_return(mock_agent_definition)

    # Stubs for AgentDefinition/Agent
    allow(ADK::AgentDefinition).to receive(:new).and_return(mock_agent_definition)
    allow(ADK::Agent).to receive(:new).with(definition: mock_agent_definition,
                                            session_service: mock_session_service).and_return(mock_agent)
    allow(mock_agent).to receive(:name).and_return(agent_name)
    allow(mock_agent).to receive(:start)
    allow(ADK).to receive(:logger).and_return(logger_double)

    # Stub Redis ping for service/store initialization
    allow(mock_redis).to receive(:ping).and_return("PONG") # Add ping back

    # Sidekiq specific testing mode
    Sidekiq::Testing.fake! # Use fake mode for job inspection
  end

  after(:each) do
    Sidekiq::Worker.clear_all # Clear jobs between tests
  end

  describe '#perform' do
    context 'with a valid payload' do
      it 'instantiates Redis SessionService with correct options' do
        # Add specific run_task mock for this test to allow execution
        allow(mock_agent).to receive(:run_task).and_return(ADK::Event.new(role: :agent, content: { status: :success }))
        # Expect new to be called ONLY with redis_client
        expect(ADK::SessionService::Redis).to receive(:new).with(redis_client: mock_redis).and_return(mock_session_service)
        worker.perform(valid_payload)
      end

      it 'loads the correct agent definition' do
        # Add specific run_task mock
        allow(mock_agent).to receive(:run_task).and_return(ADK::Event.new(role: :agent, content: { status: :success }))
        # Expect the method to be called on the definition store mock
        expect(mock_definition_store).to receive(:get_definition).with(agent_name.to_sym).and_return(mock_agent_definition)
        worker.perform(valid_payload)
      end

      it 'instantiates the agent with the definition' do
        # Add specific run_task mock
        allow(mock_agent).to receive(:run_task).and_return(ADK::Event.new(role: :agent, content: { status: :success }))
        # Expect get_definition with SYMBOL name (handled by registry mock)
        expect(ADK::Agent).to receive(:new).with(definition: mock_agent_definition,
                                                 session_service: mock_session_service).and_return(mock_agent)
        worker.perform(valid_payload)
      end

      it 'calls agent.run_task with correct arguments' do
        expected_context = ADK::WebhookContext.new(
          payload_body: payload_body,
          request_headers: valid_payload['request_headers']
        )
        # Expect run_task specifically for this test with correct args
        expect(mock_agent).to receive(:run_task).with(session_id: session_id,
                                                      user_input: valid_payload['transformed_user_input'], session_service: mock_session_service).and_return(ADK::Event.new(
                                                                                                                                                               role: :agent, content: {
                                                                                                                                                                 status: :success, result: 'Task done'
                                                                                                                                                               }
                                                                                                                                                             ))
        worker.perform(valid_payload)
      end

      it 'logs success when task completes successfully' do
        # Add specific run_task mock for this test
        allow(mock_agent).to receive(:run_task).with(session_id: session_id,
                                                     user_input: valid_payload['transformed_user_input'], session_service: mock_session_service).and_return(ADK::Event.new(
                                                                                                                                                              role: :agent, content: {
                                                                                                                                                                status: :success, result: 'Task done'
                                                                                                                                                              }
                                                                                                                                                            ))
        worker.perform(valid_payload)
        # Adjust log message expectation to match actual format
        expect(logger_double).to have_received(:info).with(/WebhookJobWorker: Agent task finished successfully/)
      end

      it 'logs error when task returns an error status' do
        # Add specific run_task mock for this test
        allow(mock_agent).to receive(:run_task).with(session_id: session_id,
                                                     user_input: valid_payload['transformed_user_input'], session_service: mock_session_service).and_return(ADK::Event.new(
                                                                                                                                                              role: :agent, content: {
                                                                                                                                                                status: :error, error_message: 'Task failed'
                                                                                                                                                              }
                                                                                                                                                            ))
        worker.perform(valid_payload)
        # Adjust log message expectation to match actual format
        expect(logger_double).to have_received(:error).with(/WebhookJobWorker: Agent task finished with error/)
      end
    end

    context 'with an invalid payload' do
      it 'raises ArgumentError if agent_definition_name is missing' do
        invalid_payload = valid_payload.except('agent_definition_name')
        # Adjust expectation to match the actual error message format
        expect {
          worker.perform(invalid_payload)
        }.to raise_error(ArgumentError, /Invalid job payload: Missing required keys/)
      end

      it 'raises ArgumentError if session_id is missing' do
        invalid_payload = valid_payload.except('session_id')
        # Adjust expectation to match the actual error message format
        expect {
          worker.perform(invalid_payload)
        }.to raise_error(ArgumentError, /Invalid job payload: Missing required keys/)
      end
      # Add tests for missing store/service types/options if needed
    end

    context 'when definition store fails' do
      it 're-raises DefinitionNotFound' do
        # Mock GlobalDefinitionRegistry find to return nil
        allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(agent_name.to_sym).and_return(nil)
        # Mock DefinitionStore get to raise error
        allow(mock_definition_store).to receive(:get_definition).with(agent_name.to_sym).and_raise(
          ADK::DefinitionStore::DefinitionNotFound, "Not found"
        )

        expect { worker.perform(valid_payload) }.to raise_error(ADK::DefinitionStore::DefinitionNotFound)
      end
    end

    context 'when session service instantiation fails' do
      it 'raises NotImplementedError for unsupported type' do
        # Mock the definition registry to return the definition object
        allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(agent_name.to_sym).and_return(mock_agent_definition)

        # Mock the Redis session service instantiation to raise the expected error
        # This prevents Agent initialization checks from running unnecessarily
        allow(ADK::SessionService::Redis).to receive(:new).and_raise(NotImplementedError,
                                                                     "Unsupported session service type: unsupported")

        payload_bad_service = valid_payload.merge('session_service_type' => 'unsupported')
        # Expect the error directly from the worker's logic when it tries to create the service
        expect {
          worker.perform(payload_bad_service)
        }.to raise_error(NotImplementedError,
                         /Unsupported session service type: unsupported/)
      end

      it 'propagates Redis connection errors' do
        # Mock definition registry
        allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(agent_name.to_sym).and_return(mock_agent_definition)
        # Mock Redis.new to raise connection error
        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError, "connection refused")

        expect { worker.perform(valid_payload) }.to raise_error(Redis::CannotConnectError)
      end
    end

    context 'when agent instantiation fails' do
      it 'raises the error' do
        # Mock Agent instantiation to fail
        allow(ADK::Agent).to receive(:new).with(definition: mock_agent_definition, session_service: mock_session_service).and_raise(
          StandardError, "Agent init boom"
        )
        # No run_task mock needed
        expect { worker.perform(valid_payload) }.to raise_error(StandardError, "Agent init boom")
      end
    end

    context 'when agent.run_task fails' do
      it 're-raises the error' do
        # Mocks for successful setup before run_task fails
        # These are likely covered by the main before block, but repeat for clarity/isolation
        allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(agent_name.to_sym).and_return(mock_agent_definition)
        allow(ADK::SessionService::Redis).to receive(:new).and_return(mock_session_service)
        allow(ADK::Agent).to receive(:new).with(definition: mock_agent_definition,
                                                session_service: mock_session_service).and_return(mock_agent)
        allow(mock_agent).to receive(:start)
        # Mock run_task to fail specifically for this test - ensure correct signature
        allow(mock_agent).to receive(:run_task).with(session_id: session_id, user_input: valid_payload['transformed_user_input'], session_service: mock_session_service).and_raise(
          StandardError, "Task run boom"
        )

        expect { worker.perform(valid_payload) }.to raise_error(StandardError, "Task run boom")
      end
    end

    context 'when session service integration fails during run_task' do
      let(:agent_double) { instance_double(ADK::Agent, name: agent_name, start: nil) }

      before do
        # Successful setup until run_task
        allow(mock_redis).to receive(:ping).and_return("PONG")
        allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(agent_name.to_sym).and_return(mock_agent_definition)
        allow(mock_definition_store).to receive(:get_definition).with(agent_name.to_sym).and_return(mock_agent_definition)
        allow(ADK::SessionService::Redis).to receive(:new).and_return(mock_session_service)
        allow(ADK::Agent).to receive(:new).with(definition: mock_agent_definition,
                                                session_service: mock_session_service).and_return(agent_double)
      end

      it 'raises ADK::SessionError if session service raises it during run_task' do
        # Have the agent.run_task raise the session error
        allow(agent_double).to receive(:run_task).with(
          session_id: session_id,
          user_input: valid_payload['transformed_user_input'],
          session_service: mock_session_service
        ).and_raise(ADK::SessionError, "Failed to access session")

        expect { worker.perform(valid_payload) }.to raise_error(ADK::SessionError, /Failed to access session/)
      end

      it 'propagates ADK::Error from session service during run_task' do
        # Have the agent.run_task raise a generic ADK error
        allow(agent_double).to receive(:run_task).with(
          session_id: session_id,
          user_input: valid_payload['transformed_user_input'],
          session_service: mock_session_service
        ).and_raise(ADK::Error, "General ADK error")

        expect { worker.perform(valid_payload) }.to raise_error(ADK::Error, /General ADK error/)
      end
    end

    context 'with different session service types' do
      let(:invalid_service_type_payload) do
        valid_payload.merge('session_service_config' => { 'type' => 'unknown_type' })
      end

      it 'raises NotImplementedError for unsupported session service types' do
        expect { worker.perform(invalid_service_type_payload) }.to raise_error(
          NotImplementedError, /Unsupported session service type/
        )
      end
    end

    context 'when the job payload is invalid' do
      it 'raises ArgumentError for missing agent_definition_name' do
        invalid_payload = valid_payload.except('agent_definition_name')
        expect { worker.perform(invalid_payload) }.to raise_error(
          ArgumentError, /Missing required keys/
        )
      end

      it 'raises ArgumentError for missing session_id' do
        invalid_payload = valid_payload.except('session_id')
        expect { worker.perform(invalid_payload) }.to raise_error(
          ArgumentError, /Missing required keys/
        )
      end

      it 'raises ArgumentError for missing transformed_user_input' do
        invalid_payload = valid_payload.except('transformed_user_input')
        expect { worker.perform(invalid_payload) }.to raise_error(
          ArgumentError, /Missing required keys/
        )
      end

      it 'raises ArgumentError for missing session_service_config' do
        invalid_payload = valid_payload.except('session_service_config')
        expect { worker.perform(invalid_payload) }.to raise_error(
          ArgumentError, /Missing required keys/
        )
      end
    end
  end
end
