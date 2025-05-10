# File: spec/adk/mcp/server/adk_agent_adapter_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'fast_mcp'
require 'redis'
require 'adk/mcp/server/adk_agent_adapter'
require 'adk/session_service/in_memory' # For testing
require 'adk/session_service/base'
require 'adk/mcp' # For logger
require 'adk/event' # Need for mocking
require 'adk/tool_registry' # Need for mocking
require 'securerandom' # Need for mocking
require 'adk/global_tool_manager' # Added require
require 'adk/agent' # Make sure Agent class is loaded for stub_const
require 'adk/definition_store/redis_store' # To mock its interface

RSpec.describe ADK::Mcp::Server::AdkAgentAdapter do
  let(:logger_spy) { spy('Logger') }
  let(:agent_name) { 'test_agent' }
  let(:session_service_instance) { ADK::SessionService::InMemory.new }
  let(:mock_redis) { instance_double(Redis, ping: true) } # Renamed for clarity
  let(:global_tool_manager_double) {
    class_double(ADK::GlobalToolManager).as_stubbed_const(transfer_nested_constants: true)
  } # Use this for mocking
  let(:agent_class_double) { class_double(ADK::Agent).as_stubbed_const }
  let(:agent_instance_double) { instance_double(ADK::Agent, start: nil, stop: nil, running?: false) }
  let(:session_double) { instance_double(ADK::Session, id: 'temp_session_123') }
  let(:securerandom_double) { class_double(SecureRandom).as_stubbed_const }
  let(:redis_store_double) { instance_double(ADK::DefinitionStore::RedisStore) }
  let(:adk_config_double) { instance_double(ADK::Configuration, definition_store: redis_store_double) }

  before do
    allow(ADK).to receive(:logger).and_return(logger_spy)
    allow(ADK).to receive(:config).and_return(adk_config_double)
    allow(Redis).to receive(:new).and_return(mock_redis) # Mock redis connection used by class & instance methods
    # Default successful agent load
    allow(mock_redis).to receive(:hmget)
      .with(/adk:agent:#{agent_name}/, 'description', 'tools', 'model')
      .and_return(['Test Agent Desc', '["tool_a"]', 'test-model'])
    # Default successful session creation/deletion by the *real* service instance
    allow(session_service_instance).to receive(:create_session).and_return(session_double)
    allow(session_service_instance).to receive(:delete_session)
    # Default successful agent instantiation
    allow(agent_class_double).to receive(:new).and_return(agent_instance_double)
    # Allow run_task by default for spy checks
    allow(agent_instance_double).to receive(:run_task)
    # Default successful tool lookup
    allow(global_tool_manager_double).to receive(:find_class).with(:tool_a).and_return(Class.new) # Mock the correct method
    # Default SecureRandom mock - allow both hex and uuid
    allow(securerandom_double).to receive(:hex).with(4).and_return('abcd') # Consistent temp user id
    allow(securerandom_double).to receive(:uuid).and_return('mock-uuid-123') # Needed for Event initialization
    # Allow necessary methods on the double
    allow(global_tool_manager_double).to receive(:find_class).with(:tool_a).and_return(Class.new) # Stub for the tool in mocked redis def
    allow(global_tool_manager_double).to receive(:reset!) # Allow reset!
    allow(global_tool_manager_double).to receive(:register_tool) # Allow registration attempts

    # This setup for :mock_adapter_tool might not be needed if tests mock redis correctly
    # class MockAdapterTool < ADK::Tool; self.explicit_tool_name = :mock_adapter_tool; end unless defined?(MockAdapterTool)
    # allow(global_tool_manager_double).to receive(:find_class).with(:mock_adapter_tool).and_return(MockAdapterTool)
  end

  describe '.wrap' do
    it 'raises ArgumentError if agent name is invalid' do
      expect {
        described_class.wrap(nil, session_service_instance)
      }.to raise_error(ArgumentError, /Agent definition name/)
      expect {
        described_class.wrap('', session_service_instance)
      }.to raise_error(ArgumentError, /Agent definition name/)
    end

    it 'raises ArgumentError if session service is invalid' do
      expect { described_class.wrap(agent_name, nil) }.to raise_error(ArgumentError, /Session service instance/)
      expect { described_class.wrap(agent_name, Object.new) }.to raise_error(ArgumentError, /Session service instance/)
    end

    it 'creates an anonymous subclass of AdkAgentAdapter' do
      adapter_class = described_class.wrap(agent_name, session_service_instance)
      expect(adapter_class).to be_a(Class)
      expect(adapter_class).to be < ADK::Mcp::Server::AdkAgentAdapter
    end

    it 'sets class instance variables on the subclass' do
      adapter_class = described_class.wrap(agent_name, session_service_instance)
      expect(adapter_class.agent_definition_name).to eq(agent_name)
      expect(adapter_class.session_service).to eq(session_service_instance)
    end

    it 'sets fast-mcp tool_name based on agent name' do
      adapter_class = described_class.wrap(agent_name, session_service_instance)
      expect(adapter_class.tool_name).to eq("run_agent_#{agent_name}")
    end

    it 'sets fast-mcp description based on agent name' do
      adapter_class = described_class.wrap(agent_name, session_service_instance)
      expect(adapter_class.description).to eq("Runs the ADK Agent '#{agent_name}' with the given prompt.")
    end

    it 'defines the :prompt argument using fast-mcp DSL' do
      adapter_class = described_class.wrap(agent_name, session_service_instance)
      # We cannot easily introspect the arguments schema set via the DSL.
      # Trust that the DSL call within .wrap sets it up correctly.
      # Subsequent tests on #call would fail if arguments weren't defined.
      # For basic check, ensure it doesn't raise error.
      expect { adapter_class.new }.not_to raise_error # Instantiation implies DSL worked
    end

    it 'logs creation info' do
      described_class.wrap(agent_name, session_service_instance)
      expect(logger_spy).to have_received(:info).with("Created fast-mcp adapter for ADK agent definition: '#{agent_name}'")
    end

    # Note: Testing the Redis connection failure within .wrap might be complex due to class methods
  end

  # --- #call Method Tests ---

  describe '#call' do
    let(:adapter_class) { described_class.wrap(agent_name, session_service_instance) }
    let(:adapter_instance) { adapter_class.new } # Instance of the *generated* class
    let(:prompt) { 'What is the weather?' }
    let(:success_event) do
      ADK::Event.new(role: :agent, content: { status: :success, result: { weather: 'sunny' } })
    end
    let(:error_event) do
      ADK::Event.new(role: :agent, content: { status: :error, error_message: 'API limit reached' })
    end
    let(:pending_event) do
      ADK::Event.new(role: :agent, content: { status: :pending, job_id: 'job_567', message: 'Processing...' })
    end
    let(:malformed_event) { ADK::Event.new(role: :user, content: 'Wrong role') }
    let(:unknown_status_event) do
      ADK::Event.new(role: :agent, content: { status: :weird, data: 'something' })
    end

    # Helper to set expectation for agent execution
    def expect_agent_run_task(return_event)
      # Override the default allow for run_task for specific return values
      allow(agent_instance_double).to receive(:run_task)
        .with(session_id: session_double.id, user_input: prompt, session_service: session_service_instance)
        .and_return(return_event)
      # Agent needs to be marked as running before stop is called in ensure
      allow(agent_instance_double).to receive(:running?).and_return(true)
    end

    context 'when execution is successful' do
      before { expect_agent_run_task(success_event) }

      it 'loads definition, creates session, runs agent, cleans up, and returns result' do
        result = adapter_instance.call(prompt: prompt)

        expect(result).to eq({ weather: 'sunny' })
        expect(Redis).to have_received(:new).at_least(:once) # Called by class method + instance method
        expect(mock_redis).to have_received(:hmget).with(/adk:agent:#{agent_name}/, 'description', 'tools', 'model')
        expect(session_service_instance).to have_received(:create_session)
          .with(app_name: agent_name, user_id: 'mcp_temp_abcd')
        expect(global_tool_manager_double).to have_received(:find_class).with(:tool_a)
        expect(agent_class_double).to have_received(:new)
          .with(hash_including(name: agent_name, tool_classes: [instance_of(Class)]))
        expect(agent_instance_double).to have_received(:start)
        expect(agent_instance_double).to have_received(:run_task)
        expect(agent_instance_double).to have_received(:stop) # From ensure block
        expect(session_service_instance).to have_received(:delete_session).with(session_id: session_double.id) # From ensure block
        expect(logger_spy).to have_received(:info).with(/Executing ADK Agent '#{agent_name}'/)
        expect(logger_spy).to have_received(:debug).with(/Agent run_task finished/)
      end

      it 'uses default model if not specified in Redis' do
        allow(mock_redis).to receive(:hmget)
          .with(/adk:agent:#{agent_name}/, 'description', 'tools', 'model')
          .and_return(['Test Agent Desc', '[]', nil]) # No model specified

        # Need to stub DEFAULT_MODEL here as well, as hmget is mocked differently
        stub_const('ADK::Agent::DEFAULT_MODEL', 'stubbed-default-model') if defined?(ADK::Agent)

        expect_agent_run_task(success_event)
        adapter_instance.call(prompt: prompt)

        expect(agent_class_double).to have_received(:new)
          .with(hash_including(model_name: ADK::Agent::DEFAULT_MODEL))
      end

      it 'handles empty tool list from Redis' do
        allow(mock_redis).to receive(:hmget)
          .with(/adk:agent:#{agent_name}/, 'description', 'tools', 'model')
          .and_return(['Test Agent Desc', '[]', 'test-model'])

        expect_agent_run_task(success_event)
        expect(global_tool_manager_double).not_to receive(:find_class) # Should not be called for empty list
        adapter_instance.call(prompt: prompt)

        expect(agent_class_double).to have_received(:new)
          .with(hash_including(tool_classes: [])) # Empty tool classes
      end

      it 'handles invalid JSON tool list from Redis' do
        allow(mock_redis).to receive(:hmget)
          .with(/adk:agent:#{agent_name}/, 'description', 'tools', 'model')
          .and_return(['Test Agent Desc', 'invalid json', 'test-model'])

        expect_agent_run_task(success_event)
        expect(global_tool_manager_double).not_to receive(:find_class) # Should not be called for invalid JSON
        adapter_instance.call(prompt: prompt)

        expect(agent_class_double).to have_received(:new)
          .with(hash_including(tool_classes: [])) # Empty tool classes
      end
    end

    context 'when agent definition is not found' do
      before do
        allow(mock_redis).to receive(:hmget)
          .with(/adk:agent:#{agent_name}/, 'description', 'tools', 'model')
          .and_return([nil, nil, nil]) # Simulate not found
        # Stub the constant temporarily for this specific context to avoid uninitialized constant error
        # Ensure ADK::Agent is loaded before stubbing its constant
        stub_const('ADK::Agent::DEFAULT_MODEL', 'stubbed-default-model') if defined?(ADK::Agent)
      end

      it 'raises an error and does not attempt session creation or agent run' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError,
                          /Failed to run agent '#{agent_name}': Agent definition '#{agent_name}' not found/)

        expect(session_service_instance).not_to have_received(:create_session)
        expect(agent_class_double).not_to have_received(:new)
        expect(agent_instance_double).not_to have_received(:run_task) # This should pass now
        expect(logger_spy).to have_received(:error).with(/Error during AdkAgentAdapter call.*ADK::Mcp::Error - Agent definition '#{agent_name}' not found/)
        # Ensure cleanup still runs, although session/agent wouldn't exist
        expect(agent_instance_double).not_to have_received(:stop) # Agent not created
        expect(session_service_instance).not_to have_received(:delete_session) # Session not created
      end
    end

    context 'when Redis connection fails during definition load' do
      before do
        # This error happens in the class method connect_redis
        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError, 'Connection refused')
      end

      it 'raises an error' do
        # Need to re-wrap because the error happens in class method context within #call
        adapter_class_for_test = described_class.wrap(agent_name, session_service_instance)
        adapter_instance_for_test = adapter_class_for_test.new

        expect { adapter_instance_for_test.call(prompt: prompt) }
          .to raise_error(StandardError, /Failed to run agent.*Redis connection failed: Connection refused/)

        expect(logger_spy).to have_received(:error).with(/Error during AdkAgentAdapter call.*ADK::Mcp::Error - Redis connection failed/)
        expect(session_service_instance).not_to have_received(:create_session)
      end
    end

    context 'when a defined tool is not found in the registry' do
      before do
        allow(global_tool_manager_double).to receive(:find_class).with(:tool_a).and_return(nil) # Correct mock
        expect_agent_run_task(success_event) # Agent run should still happen, but with fewer tools
      end

      it 'logs a warning and proceeds with found tools' do
        adapter_instance.call(prompt: prompt)

        expect(logger_spy).to have_received(:warn).with(/Some tools defined for agent '#{agent_name}' were not found/)
        # Agent should be initialized with an empty tool list in this case
        expect(agent_class_double).to have_received(:new).with(hash_including(tool_classes: []))
        # Ensure execution completes
        expect(agent_instance_double).to have_received(:run_task) # This should pass now
        expect(session_service_instance).to have_received(:delete_session)
      end
    end

    context 'when session creation fails' do
      before do
        allow(session_service_instance).to receive(:create_session)
          .and_raise(StandardError, 'Session service unavailable')
      end

      it 'raises an error and does not run the agent' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Failed to run agent.*Session service unavailable/)

        expect(agent_class_double).not_to have_received(:new)
        expect(agent_instance_double).not_to have_received(:run_task) # This should pass now
        expect(logger_spy).to have_received(:error).with(/Error during AdkAgentAdapter call.*StandardError - Session service unavailable/)
        # Ensure cleanup doesn't try to delete a non-existent session
        expect(session_service_instance).not_to have_received(:delete_session)
      end
    end

    context 'when agent execution returns an error status' do
      before { expect_agent_run_task(error_event) }

      it 'raises an error with the message from the event' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Agent Error: API limit reached/)

        expect(logger_spy).to have_received(:error).with("Agent '#{agent_name}' execution failed: API limit reached")
        expect(logger_spy).to have_received(:error).with(/Error during AdkAgentAdapter call.*StandardError - Agent Error: API limit reached/)
        # Ensure cleanup still happens
        expect(agent_instance_double).to have_received(:stop)
        expect(session_service_instance).to have_received(:delete_session)
      end

      it 'raises an error with a default message if not provided' do
        error_event_no_msg = ADK::Event.new(role: :agent, content: { status: :error, error_message: nil })
        expect_agent_run_task(error_event_no_msg)

        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Agent Error: Agent execution failed./)
      end
    end

    context 'when agent execution returns a pending status' do
      before { expect_agent_run_task(pending_event) }

      it 'returns the pending status structure' do
        result = adapter_instance.call(prompt: prompt)

        expect(result).to eq({ status: 'pending', job_id: 'job_567', message: 'Processing...' })
        expect(logger_spy).to have_received(:warn).with(/Agent '#{agent_name}' execution ended with pending status/)
        # Ensure cleanup still happens
        expect(agent_instance_double).to have_received(:stop)
        expect(session_service_instance).to have_received(:delete_session)
      end

      it 'returns pending status with default message if not provided' do
        pending_event_no_msg = ADK::Event.new(role: :agent, content: { status: :pending, job_id: 'job_567' })
        expect_agent_run_task(pending_event_no_msg)

        result = adapter_instance.call(prompt: prompt)
        expect(result[:message]).to eq('Agent task resulted in a pending job.')
      end
    end

    context 'when agent execution returns an unexpected event format' do
      before { expect_agent_run_task(malformed_event) }

      it 'raises an error' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Agent task finished with unexpected event format/)

        expect(logger_spy).to have_received(:error).with(/Error during AdkAgentAdapter call.*StandardError - Agent task finished with unexpected event format/)
        expect(agent_instance_double).to have_received(:stop)
        expect(session_service_instance).to have_received(:delete_session)
      end
    end

    context 'when agent execution returns an unknown status' do
      before { expect_agent_run_task(unknown_status_event) }

      it 'raises an error' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Agent task finished with unknown status: weird/)

        expect(logger_spy).to have_received(:error).with(/Error during AdkAgentAdapter call.*StandardError - Agent task finished with unknown status: weird/)
        expect(agent_instance_double).to have_received(:stop)
        expect(session_service_instance).to have_received(:delete_session)
      end
    end

    context 'when agent start fails' do
      before do
        allow(agent_instance_double).to receive(:start).and_raise('Start failed')
      end

      it 'raises an error and ensures cleanup is attempted' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Failed to run agent.*Start failed/)

        expect(agent_instance_double).not_to have_received(:run_task) # This should pass now
        # Ensure cleanup is still called, but stop shouldn't be called if start failed
        expect(agent_instance_double).not_to have_received(:stop) # Changed expectation
        expect(session_service_instance).to have_received(:delete_session)
        expect(logger_spy).to have_received(:error).with(/Error during AdkAgentAdapter call.*RuntimeError - Start failed/)
      end
    end

    context 'when agent run_task fails with an exception' do
      before do
        # Override the default allow for run_task to raise error
        allow(agent_instance_double).to receive(:run_task).and_raise('Run task failed')
        allow(agent_instance_double).to receive(:running?).and_return(true) # Assume it was running
      end

      it 'raises an error and ensures cleanup' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Failed to run agent.*Run task failed/)

        expect(agent_instance_double).to have_received(:stop)
        expect(session_service_instance).to have_received(:delete_session)
        expect(logger_spy).to have_received(:error).with(/Error during AdkAgentAdapter call.*RuntimeError - Run task failed/)
      end
    end

    # --- Cleanup Error Handling (Ensure Block) ---

    context 'when agent stop fails during cleanup' do
      before do
        expect_agent_run_task(success_event) # Normal execution first
        allow(agent_instance_double).to receive(:stop).and_raise('Stop error')
      end

      it 'logs the stop error but still attempts session deletion and returns result' do
        result = adapter_instance.call(prompt: prompt)

        expect(result).to eq({ weather: 'sunny' }) # Original result should still return
        expect(logger_spy).to have_received(:error).with('Error stopping agent runtime during cleanup: Stop error')
        # Ensure session deletion was still attempted
        expect(session_service_instance).to have_received(:delete_session).with(session_id: session_double.id)
      end
    end

    context 'when session deletion fails during cleanup' do
      before do
        expect_agent_run_task(success_event) # Normal execution first
        allow(session_service_instance).to receive(:delete_session).and_raise('Deletion error')
      end

      it 'logs the deletion error but still returns the result' do
        result = adapter_instance.call(prompt: prompt)

        expect(result).to eq({ weather: 'sunny' }) # Original result should still return
        expect(logger_spy).to have_received(:error).with("Error deleting temporary session #{session_double.id}: Deletion error")
        # Ensure agent stop was still attempted (before deletion)
        expect(agent_instance_double).to have_received(:stop)
      end
    end

    context 'when both agent stop and session deletion fail during cleanup' do
      before do
        expect_agent_run_task(success_event) # Normal execution first
        allow(agent_instance_double).to receive(:stop).and_raise('Stop error')
        allow(session_service_instance).to receive(:delete_session).and_raise('Deletion error')
      end

      it 'logs both errors and returns the result' do
        result = adapter_instance.call(prompt: prompt)

        expect(result).to eq({ weather: 'sunny' }) # Original result should still return
        expect(logger_spy).to have_received(:error).with('Error stopping agent runtime during cleanup: Stop error')
        expect(logger_spy).to have_received(:error).with("Error deleting temporary session #{session_double.id}: Deletion error")
      end
    end

    context 'when called without using .wrap first (directly on base class)' do
      it 'raises NotImplementedError' do
        base_instance = ADK::Mcp::Server::AdkAgentAdapter.new
        expect { base_instance.call(prompt: prompt) }
          .to raise_error(NotImplementedError, /must be configured using .wrap first/)
      end
    end
  end
end
