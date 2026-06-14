# File: spec/legate/mcp/server/legate_agent_adapter_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'fast_mcp'
require 'legate/mcp/server/legate_agent_adapter'
require 'legate/session_service/in_memory' # For testing
require 'legate/session_service/base'
require 'legate/mcp' # For logger
require 'legate/event' # Need for mocking
require 'legate/tool_registry' # Need for mocking
require 'securerandom' # Need for mocking
require 'legate/global_tool_manager' # Added require
require 'legate/agent' # Make sure Agent class is loaded for stub_const

RSpec.describe Legate::Mcp::Server::LegateAgentAdapter do
  let(:logger_spy) { spy('Logger') }
  let(:agent_name) { 'test_agent' }
  let(:session_service_instance) { Legate::SessionService::InMemory.new }
  let(:global_tool_manager_double) {
    class_double(Legate::GlobalToolManager).as_stubbed_const(transfer_nested_constants: true)
  } # Use this for mocking
  let(:global_definition_registry_double) {
    class_double(Legate::GlobalDefinitionRegistry).as_stubbed_const(transfer_nested_constants: true)
  }
  let(:agent_class_double) { class_double(Legate::Agent).as_stubbed_const }
  let(:agent_instance_double) { instance_double(Legate::Agent, start: nil, stop: nil, running?: false) }
  let(:session_double) { instance_double(Legate::Session, id: 'temp_session_123') }
  let(:securerandom_double) { class_double(SecureRandom).as_stubbed_const }

  let(:mock_definition_object) do
    instance_double(Legate::AgentDefinition,
                    name: agent_name.to_sym,
                    description: 'Test Agent Description',
                    instruction: 'Perform tasks.',
                    tool_names: [:tool_a].to_set,
                    model_name: 'gemini-pro',
                    fallback_mode: :error,
                    mcp_servers: [],
                    sub_agent_names: Set.new,
                    output_key: nil,
                    webhook_enabled: false,
                    webhook_validator: nil,
                    webhook_secret: nil,
                    webhook_transformer: nil,
                    webhook_session_extractor: nil)
  end

  let(:mock_definition_no_model) do
    instance_double(Legate::AgentDefinition,
                    name: agent_name.to_sym,
                    description: 'Test Agent Description',
                    instruction: 'Perform tasks.',
                    tool_names: [:tool_a].to_set,
                    model_name: nil,
                    fallback_mode: :error,
                    mcp_servers: [],
                    sub_agent_names: Set.new,
                    output_key: nil,
                    webhook_enabled: false,
                    webhook_validator: nil,
                    webhook_secret: nil,
                    webhook_transformer: nil,
                    webhook_session_extractor: nil)
  end

  let(:mock_definition_no_tools) do
    instance_double(Legate::AgentDefinition,
                    name: agent_name.to_sym,
                    description: 'Test Agent Description',
                    instruction: 'Perform tasks.',
                    tool_names: Set.new,
                    model_name: 'gemini-pro',
                    fallback_mode: :error,
                    mcp_servers: [],
                    sub_agent_names: Set.new,
                    output_key: nil,
                    webhook_enabled: false,
                    webhook_validator: nil,
                    webhook_secret: nil,
                    webhook_transformer: nil,
                    webhook_session_extractor: nil)
  end

  before do
    allow(Legate).to receive(:logger).and_return(logger_spy)
    # Default successful definition lookup
    allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_object)
    allow(global_definition_registry_double).to receive(:respond_to?).with(:get_definition).and_return(true)
    allow(global_definition_registry_double).to receive(:get_definition).and_return(nil)
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
    allow(global_tool_manager_double).to receive(:reset!) # Allow reset!
    allow(global_tool_manager_double).to receive(:register_tool) # Allow registration attempts
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

    it 'creates an anonymous subclass of LegateAgentAdapter' do
      adapter_class = described_class.wrap(agent_name, session_service_instance)
      expect(adapter_class).to be_a(Class)
      expect(adapter_class).to be < Legate::Mcp::Server::LegateAgentAdapter
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
      expect(adapter_class.description).to eq("Runs the Legate Agent '#{agent_name}' with the given prompt.")
    end

    it 'defines the :prompt argument using fast-mcp DSL' do
      adapter_class = described_class.wrap(agent_name, session_service_instance)
      expect { adapter_class.new }.not_to raise_error # Instantiation implies DSL worked
    end

    it 'logs creation info' do
      described_class.wrap(agent_name, session_service_instance)
      expect(logger_spy).to have_received(:info).with("Created fast-mcp adapter for Legate agent definition: '#{agent_name}'")
    end
  end

  # --- #call Method Tests ---

  describe '#call' do
    let(:adapter_class) { described_class.wrap(agent_name, session_service_instance) }
    let(:adapter_instance) { adapter_class.new } # Instance of the *generated* class
    let(:prompt) { 'What is the weather?' }
    let(:success_event) do
      Legate::Event.new(role: :agent, content: { status: :success, result: { weather: 'sunny' } })
    end
    let(:error_event) do
      Legate::Event.new(role: :agent, content: { status: :error, error_message: 'API limit reached' })
    end
    let(:pending_event) do
      Legate::Event.new(role: :agent, content: { status: :pending, job_id: 'job_567', message: 'Processing...' })
    end
    let(:malformed_event) { Legate::Event.new(role: :user, content: 'Wrong role') }
    let(:unknown_status_event) do
      Legate::Event.new(role: :agent, content: { status: :weird, data: 'something' })
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
      before do
        expect_agent_run_task(success_event)
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_object)
      end

      it 'loads definition, creates session, runs agent, cleans up, and returns result' do
        result = adapter_instance.call(prompt: prompt)

        expect(result).to eq({ weather: 'sunny' })
        expect(session_service_instance).to have_received(:create_session)
          .with(app_name: agent_name, user_id: 'mcp_temp_abcd')
        expect(agent_class_double).to have_received(:new)
          .with(hash_including(
                  definition: mock_definition_object,
                  session_service: session_service_instance
                ))
        expect(agent_instance_double).to have_received(:start)
        expect(agent_instance_double).to have_received(:run_task)
        expect(agent_instance_double).to have_received(:stop) # From ensure block
        expect(session_service_instance).to have_received(:delete_session).with(session_id: session_double.id) # From ensure block
        expect(logger_spy).to have_received(:info).with(/Executing Legate Agent '#{agent_name}'/)
        expect(logger_spy).to have_received(:debug).with(/Agent run_task finished/)
      end

      it 'uses default model if not specified in definition' do
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_no_model)
        stub_const('Legate::Agent::DEFAULT_MODEL', 'stubbed-default-model') if defined?(Legate::Agent)

        expect_agent_run_task(success_event)
        adapter_instance.call(prompt: prompt)

        expect(agent_class_double).to have_received(:new)
          .with(hash_including(
                  definition: mock_definition_no_model,
                  session_service: session_service_instance
                ))
      end

      it 'handles empty tool list in definition' do
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_no_tools)

        expect_agent_run_task(success_event)
        adapter_instance.call(prompt: prompt)

        expect(agent_class_double).to have_received(:new)
          .with(hash_including(
                  definition: mock_definition_no_tools,
                  session_service: session_service_instance
                ))
      end
    end

    context 'when agent definition is not found' do
      before do
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(nil)
        allow(global_definition_registry_double).to receive(:get_definition).with(agent_name).and_return(nil)
        stub_const('Legate::Agent::DEFAULT_MODEL', 'stubbed-default-model') if defined?(Legate::Agent)
      end

      it 'raises an error and does not attempt session creation or agent run' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError,
                          /Failed to run agent '#{agent_name}': Agent definition '#{agent_name}' not found/)

        expect(session_service_instance).not_to have_received(:create_session)
        expect(agent_class_double).not_to have_received(:new)
        expect(agent_instance_double).not_to have_received(:run_task)
        expect(logger_spy).to have_received(:error).with(/Error during LegateAgentAdapter call.*Agent definition '#{agent_name}' not found/)
        # Ensure cleanup still runs, although session/agent wouldn't exist
        expect(agent_instance_double).not_to have_received(:stop) # Agent not created
        expect(session_service_instance).not_to have_received(:delete_session) # Session not created
      end
    end

    context 'when session creation fails' do
      before do
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_object)
        allow(session_service_instance).to receive(:create_session)
          .and_raise(StandardError, 'Session service unavailable')
      end

      it 'raises an error and does not run the agent' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Failed to run agent.*Session service unavailable/)

        expect(agent_class_double).not_to have_received(:new)
        expect(agent_instance_double).not_to have_received(:run_task)
        expect(logger_spy).to have_received(:error).with(/Error during LegateAgentAdapter call.*StandardError - Session service unavailable/)
        # Ensure cleanup doesn't try to delete a non-existent session
        expect(session_service_instance).not_to have_received(:delete_session)
      end
    end

    context 'when agent execution returns an error status' do
      before do
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_object)
        expect_agent_run_task(error_event)
      end

      it 'raises an error with the message from the event' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Agent Error: API limit reached/)

        expect(logger_spy).to have_received(:error).with("Agent '#{agent_name}' execution failed: API limit reached")
        expect(logger_spy).to have_received(:error).with(/Error during LegateAgentAdapter call.*StandardError - Agent Error: API limit reached/)
        # Ensure cleanup still happens
        expect(agent_instance_double).to have_received(:stop)
        expect(session_service_instance).to have_received(:delete_session)
      end

      it 'raises an error with a default message if not provided' do
        error_event_no_msg = Legate::Event.new(role: :agent, content: { status: :error, error_message: nil })
        expect_agent_run_task(error_event_no_msg)

        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Agent Error: Agent execution failed./)
      end
    end

    context 'when agent execution returns a pending status' do
      before do
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_object)
        expect_agent_run_task(pending_event)
      end

      it 'returns the pending status structure' do
        result = adapter_instance.call(prompt: prompt)

        expect(result).to eq({ status: 'pending', job_id: 'job_567', message: 'Processing...' })
        expect(logger_spy).to have_received(:warn).with(/Agent '#{agent_name}' execution ended with pending status/)
        # Ensure cleanup still happens
        expect(agent_instance_double).to have_received(:stop)
        expect(session_service_instance).to have_received(:delete_session)
      end

      it 'returns pending status with default message if not provided' do
        pending_event_no_msg = Legate::Event.new(role: :agent, content: { status: :pending, job_id: 'job_567' })
        expect_agent_run_task(pending_event_no_msg)

        result = adapter_instance.call(prompt: prompt)
        expect(result[:message]).to eq('Agent task resulted in a pending job.')
      end
    end

    context 'when agent execution returns an unexpected event format' do
      before do
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_object)
        expect_agent_run_task(malformed_event)
      end

      it 'raises an error' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Agent task finished with unexpected event format/)

        expect(logger_spy).to have_received(:error).with(/Error during LegateAgentAdapter call.*StandardError - Agent task finished with unexpected event format/)
        expect(agent_instance_double).to have_received(:stop)
        expect(session_service_instance).to have_received(:delete_session)
      end
    end

    context 'when agent execution returns an unknown status' do
      before do
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_object)
        expect_agent_run_task(unknown_status_event)
      end

      it 'raises an error' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Agent task finished with unknown status: weird/)

        expect(logger_spy).to have_received(:error).with(/Error during LegateAgentAdapter call.*StandardError - Agent task finished with unknown status: weird/)
        expect(agent_instance_double).to have_received(:stop)
        expect(session_service_instance).to have_received(:delete_session)
      end
    end

    context 'when agent start fails' do
      before do
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_object)
        allow(agent_instance_double).to receive(:start).and_raise('Start failed')
      end

      it 'raises an error and ensures cleanup is attempted' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Failed to run agent.*Start failed/)

        expect(agent_instance_double).not_to have_received(:run_task)
        # Ensure cleanup is still called, but stop shouldn't be called if start failed
        expect(agent_instance_double).not_to have_received(:stop) # Changed expectation
        expect(session_service_instance).to have_received(:delete_session)
        expect(logger_spy).to have_received(:error).with(/Error during LegateAgentAdapter call.*RuntimeError - Start failed/)
      end
    end

    context 'when agent run_task fails with an exception' do
      before do
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_object)
        # Override the default allow for run_task to raise error
        allow(agent_instance_double).to receive(:run_task).and_raise('Run task failed')
        allow(agent_instance_double).to receive(:running?).and_return(true) # Assume it was running
      end

      it 'raises an error and ensures cleanup' do
        expect { adapter_instance.call(prompt: prompt) }
          .to raise_error(StandardError, /Failed to run agent.*Run task failed/)

        expect(agent_instance_double).to have_received(:stop)
        expect(session_service_instance).to have_received(:delete_session)
        expect(logger_spy).to have_received(:error).with(/Error during LegateAgentAdapter call.*RuntimeError - Run task failed/)
      end
    end

    # --- Cleanup Error Handling (Ensure Block) ---

    context 'when agent stop fails during cleanup' do
      before do
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_object)
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
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_object)
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
        allow(global_definition_registry_double).to receive(:find).with(agent_name.to_sym).and_return(mock_definition_object)
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
        base_instance = Legate::Mcp::Server::LegateAgentAdapter.new
        expect { base_instance.call(prompt: prompt) }
          .to raise_error(NotImplementedError, /must be configured using .wrap first/)
      end
    end
  end
end
