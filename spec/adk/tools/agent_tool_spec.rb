# File: spec/adk/tools/agent_tool_spec.rb
require 'spec_helper'
require 'redis' # Need this for Redis::CannotConnectError

RSpec.describe ADK::Tools::AgentTool do
  subject(:tool) { described_class.new }

  let(:target_agent_name) { 'calculator_agent' }
  let(:task_to_delegate) { 'what is 10 * 5' }
  let(:params) { { target_agent_name: target_agent_name, task: task_to_delegate } }

  # --- Mocks ---
  let(:mock_redis) { instance_double(Redis) }
  let(:mock_target_agent) { instance_double(ADK::Agent) }
  let(:mock_calculator_tool) { instance_double(ADK::Tools::Calculator) }
  let(:target_definition) do
    {
      'description' => 'A calculator',
      'tools' => '["calculator"]',
      'model' => 'gemini-test-model'
    }
  end
  let(:target_key) { "adk:agent:#{target_agent_name}" }
  let(:expected_target_result) { { status: :success, result: 50.0 } }

  # Session-related mocks
  let(:session_id) { 'delegate-session-123' }
  let(:mock_session) { instance_double(ADK::Session, id: session_id, events: []) }
  let(:mock_session_service) { instance_double(ADK::SessionService::InMemory) }
  let(:mock_agent_event) { instance_double(ADK::Event, role: :agent, content: expected_target_result) }

  # --- Context Mocking ---
  let(:mock_executing_registry) { instance_double(ADK::ToolRegistry) }
  let(:mock_context) {
    instance_double(ADK::ToolContext,
                    session_id: 'outer-session', # Different from delegate session
                    user_id: 'outer-user',
                    app_name: 'outer-agent',
                    tool_registry: mock_executing_registry,
                    to_h: { session_id: 'outer-session', user_id: 'outer-user', app_name: 'outer-agent' })
  }
  # --- End Context Mocking ---

  before do
    # Mock Redis connection and data loading by default
    allow(Redis).to receive(:new).and_return(mock_redis)
    allow(mock_redis).to receive(:ping)
    allow(mock_redis).to receive(:hmget)
      .with(target_key, 'description', 'tools', 'model')
      .and_return(target_definition.values)

    # Mock ToolRegistry find_class on the *executing* agent's registry
    # This registry is passed via context now
    # Remove stub for global ADK::ToolRegistry.create_instance
    # allow(ADK::ToolRegistry).to receive(:create_instance).with(:calculator).and_return(mock_calculator_tool)
    # Ensure ADK::Tools::Calculator is loaded for the test
    require_relative '../../../lib/adk/tools/calculator' unless defined?(ADK::Tools::Calculator)
    allow(mock_executing_registry).to receive(:find_class).with(:calculator).and_return(ADK::Tools::Calculator)

    # Mock Agent instantiation for the target agent
    allow(ADK::Agent).to receive(:new).and_call_original # Allow normal agent init
    allow(ADK::Agent).to receive(:new)
      .with(hash_including(name: matching(/#{target_agent_name}_delegated/),
                           model_name: 'gemini-test-model'))
      .and_return(mock_target_agent)

    # Mock methods on the target agent instance
    # Change add_tool expectation to register_tool_class
    # allow(mock_target_agent).to receive(:add_tool).with(mock_calculator_tool)
    allow(mock_target_agent).to receive(:register_tool_class).with(ADK::Tools::Calculator)
    allow(mock_target_agent).to receive(:start)

    # Mock session service
    allow(ADK::SessionService::InMemory).to receive(:new).and_return(mock_session_service)
    allow(mock_session_service).to receive(:create_session).and_return(mock_session)
    allow(mock_session_service).to receive(:get_session).with(session_id: session_id).and_return(mock_session)
    allow(mock_session_service).to receive(:append_event).and_return(true)

    # Mock run_task with session parameters to return the expected result
    allow(mock_target_agent).to receive(:run_task)
      .with(session_id: session_id, user_input: task_to_delegate, session_service: mock_session_service)
      .and_return(mock_agent_event)
  end

  describe '#initialize' do
    # Basic checks
    it { expect(tool.name).to eq(:delegate_task) }
    it { expect(tool.parameters.keys).to contain_exactly(:target_agent_name, :task) }
    it { expect(tool.parameters[:target_agent_name][:required]).to be true }
    it { expect(tool.parameters[:task][:required]).to be true }
  end

  describe '#execute' do
    context 'when delegation is successful' do
      it 'connects to redis, loads definition, instantiates agent, adds tools, runs task' do
        expect(Redis).to receive(:new).and_return(mock_redis)
        expect(mock_redis).to receive(:ping)
        expect(mock_redis).to receive(:hmget).with(target_key, 'description', 'tools',
                                                   'model').and_return(target_definition.values)
        expect(ADK::Agent).to receive(:new).with(hash_including(name: matching(/#{target_agent_name}_delegated/))).and_return(mock_target_agent)
        # Expect find_class on the registry passed via context
        expect(mock_executing_registry).to receive(:find_class).with(:calculator).and_return(ADK::Tools::Calculator)
        # Expect register_tool_class on the temporary agent
        expect(mock_target_agent).to receive(:register_tool_class).with(ADK::Tools::Calculator)
        expect(mock_target_agent).to receive(:start)

        # Expect session service creation
        expect(ADK::SessionService::InMemory).to receive(:new).and_return(mock_session_service)
        expect(mock_session_service).to receive(:create_session).and_return(mock_session)

        # Updated expectation for run_task with session parameters
        expect(mock_target_agent).to receive(:run_task)
          .with(session_id: session_id, user_input: task_to_delegate, session_service: mock_session_service)
          .and_return(mock_agent_event)

        tool.execute(params, mock_context)
      end

      it 'returns a success hash containing the target agents result' do
        result = tool.execute(params, mock_context)
        # Check the overall structure
        expect(result[:status]).to eq(:success)
        # Check that the result is the mock_agent_event
        expect(result[:result]).to eq(mock_agent_event)
        # Verify that the mock_agent_event content has the expected_target_result
        expect(mock_agent_event.content).to eq(expected_target_result)
      end
    end

    context 'when target agent definition is not found' do
      before do
        allow(mock_redis).to receive(:hmget).with(target_key, 'description', 'tools', 'model').and_return([nil, nil, nil]) # Simulate not found
      end

      it 'raises ToolArgumentError' do
        expect {
          tool.execute(params, mock_context)
        }.to raise_error(ADK::ToolArgumentError, /Target agent definition '#{target_agent_name}' not found/)
      end
    end

    context 'when redis connection fails' do
      before do
        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError.new("Cannot connect"))
      end

      it 'raises ToolError' do
        expect {
          tool.execute(params, mock_context)
        }.to raise_error(ADK::ToolError, /Could not connect to Redis/)
      end
    end

    context 'when target agent has invalid tools JSON' do
      let(:invalid_target_definition) { target_definition.merge('tools' => '[invalid json') }
      before do
        allow(mock_redis).to receive(:hmget).with(target_key, 'description', 'tools',
                                                  'model').and_return(invalid_target_definition.values)
      end

      it 'raises ToolArgumentError' do
        expect {
          tool.execute(params, mock_context)
        }.to raise_error(ADK::ToolArgumentError, /Failed to parse tools JSON/)
      end
    end

    context 'when target agent task execution raises an error' do
      let(:target_error) { StandardError.new("Target agent failed!") }
      before do
        allow(mock_target_agent).to receive(:run_task)
          .with(session_id: session_id, user_input: task_to_delegate, session_service: mock_session_service)
          .and_raise(target_error)
      end

      it 'raises ToolError capturing the exception' do
        expect {
          tool.execute(params, mock_context)
        }.to raise_error(ADK::ToolError, /Unexpected error during delegation.*StandardError - Target agent failed!/)
      end
    end

    context 'with missing parameters (base validation)' do
      it 'raises ADK::Error if target_agent_name is missing' do
        expect {
          tool.execute({ task: task_to_delegate }, mock_context)
        }.to raise_error(ADK::Error, /Missing required parameters: target_agent_name/)
      end

      it 'raises ADK::Error if task is missing' do
        expect {
          tool.execute({ target_agent_name: target_agent_name }, mock_context)
        }.to raise_error(ADK::Error, /Missing required parameters: task/)
      end
    end
  end
end
