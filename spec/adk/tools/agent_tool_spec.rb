# frozen_string_literal: true

# File: spec/adk/tools/agent_tool_spec.rb
require 'spec_helper'

RSpec.describe ADK::Tools::AgentTool do
  let(:tool_class) { described_class } # Use class reference
  let(:metadata) { tool_class.tool_metadata }

  let(:target_agent_name) { :calculator_agent } # Use symbol
  let(:task_to_delegate) { 'what is 10 * 5' }
  let(:params) {
    { target_agent_name: target_agent_name.to_s, task: task_to_delegate }
  } # CLI/Planner likely uses string

  # --- Mocks ---
  let(:mock_target_agent) { instance_double(ADK::Agent) }
  let(:mock_calculator_tool) { instance_double(ADK::Tools::Calculator) }
  let(:target_definition_hash) do # Use a hash, not JSON strings
    {
      description: 'A calculator',
      tools: ['calculator'], # Array of strings
      model: 'gemini-test-model'
    }
  end
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
                    session_id: 'outer-session',
                    user_id: 'outer-user',
                    app_name: 'outer-agent',
                    tool_registry: mock_executing_registry,
                    to_h: {})
  }
  # --- End Context Mocking ---

  before do
    # Stub AgentDefinitionStore lookup
    # Default: Agent not found
    # Expect the string name from params, but allow symbol for flexibility
    allow(ADK::AgentDefinitionStore).to receive(:find).with(target_agent_name.to_s).and_return(nil)
    allow(ADK::AgentDefinitionStore).to receive(:load_from_redis).with(target_agent_name.to_s).and_return(nil)

    # Mock ToolRegistry find_class on the *executing* agent's registry
    require_relative '../../../lib/adk/tools/calculator' unless defined?(ADK::Tools::Calculator)
    allow(mock_executing_registry).to receive(:find_class).with(:calculator).and_return(ADK::Tools::Calculator)

    # Mock Agent instantiation for the target agent
    allow(ADK::Agent).to receive(:new).and_call_original
    allow(ADK::Agent).to receive(:new)
      .with(hash_including(name: matching(/#{target_agent_name}_delegated/),
                           model_name: target_definition_hash[:model],
                           description: target_definition_hash[:description]))
      .and_return(mock_target_agent)

    # Mock methods on the target agent instance
    allow(mock_target_agent).to receive(:register_tool_class).with(ADK::Tools::Calculator)
    allow(mock_target_agent).to receive(:start)

    # Mock session service
    allow(ADK::SessionService::InMemory).to receive(:new).and_return(mock_session_service)
    allow(mock_session_service).to receive(:create_session).and_return(mock_session)
    allow(mock_session_service).to receive(:get_session).with(session_id: session_id).and_return(mock_session)
    allow(mock_session_service).to receive(:append_event).and_return(true)

    # Mock run_task with session parameters
    allow(mock_target_agent).to receive(:run_task)
      .with(session_id: session_id, user_input: task_to_delegate, session_service: mock_session_service)
      .and_return(mock_agent_event)

    # Mock logger
    allow(ADK.logger).to receive(:debug)
    allow(ADK.logger).to receive(:info)
    allow(ADK.logger).to receive(:warn)
    allow(ADK.logger).to receive(:error)
  end

  # Test Class Metadata directly
  describe 'Class Metadata' do
    it 'has the correct explicit name' do
      expect(metadata[:name]).to eq(:delegate_task)
    end
    it 'has the correct description' do
      expect(metadata[:description]).to include('Delegates a specified task')
    end
    it 'defines parameters correctly' do
      expect(metadata[:parameters].keys).to contain_exactly(:target_agent_name, :task)
      expect(metadata[:parameters][:target_agent_name][:required]).to be true
      expect(metadata[:parameters][:task][:required]).to be true
    end
  end

  describe '#execute' do
    subject(:tool) { tool_class.new } # Create instance for execution tests

    context 'when delegation is successful' do
      before do
        # Stub definition store to return the definition, expect string name
        allow(ADK::AgentDefinitionStore).to receive(:find).with(target_agent_name.to_s).and_return(target_definition_hash)
      end

      it 'loads definition, instantiates agent, adds tools, runs task' do
        # Verify store lookup with string name
        expect(ADK::AgentDefinitionStore).to receive(:find).with(target_agent_name.to_s).and_return(target_definition_hash)
        # Verify agent instantiation
        expect(ADK::Agent).to receive(:new)
          .with(hash_including(name: matching(/#{target_agent_name}_delegated/),
                               model_name: target_definition_hash[:model],
                               description: target_definition_hash[:description]))
          .and_return(mock_target_agent)
        # Verify tool registration
        expect(mock_executing_registry).to receive(:find_class).with(:calculator).and_return(ADK::Tools::Calculator)
        expect(mock_target_agent).to receive(:register_tool_class).with(ADK::Tools::Calculator)
        # Verify agent start
        expect(mock_target_agent).to receive(:start)
        # Verify session creation
        expect(ADK::SessionService::InMemory).to receive(:new).and_return(mock_session_service)
        expect(mock_session_service).to receive(:create_session).and_return(mock_session)
        # Verify task execution
        expect(mock_target_agent).to receive(:run_task)
          .with(session_id: session_id, user_input: task_to_delegate, session_service: mock_session_service)
          .and_return(mock_agent_event)

        tool.execute(params, mock_context)
      end

      it 'returns a success hash containing the target agents result' do
        result = tool.execute(params, mock_context)
        expect(result[:status]).to eq(:success)
        expect(result[:result]).to eq(mock_agent_event.content)
      end
    end

    context 'when definition is loaded from Redis (not memory)' do
      before do
        # Stub find to return nil, load_from_redis to return definition
        allow(ADK::AgentDefinitionStore).to receive(:find).with(target_agent_name.to_s).and_return(nil)
        allow(ADK::AgentDefinitionStore).to receive(:load_from_redis).with(target_agent_name.to_s).and_return(target_definition_hash)
      end

      it 'successfully loads from Redis and executes' do
        # Minimal check: ensure it doesn't raise 'not found' and returns success
        expect(ADK::AgentDefinitionStore).to receive(:load_from_redis).with(target_agent_name.to_s).and_return(target_definition_hash)
        result = tool.execute(params, mock_context)
        expect(result[:status]).to eq(:success)
        expect(result[:result]).to eq(expected_target_result)
      end
    end

    context 'when target agent definition is not found' do
      before do
        # Default mocks already handle not found case (return nil)
        # Ensure mocks expect string name
        allow(ADK::AgentDefinitionStore).to receive(:find).with(target_agent_name.to_s).and_return(nil)
        allow(ADK::AgentDefinitionStore).to receive(:load_from_redis).with(target_agent_name.to_s).and_return(nil)
      end

      it 'raises ToolArgumentError' do
        expect {
          tool.execute(params, mock_context)
        }.to raise_error(ADK::ToolArgumentError, /Target agent definition 'calculator_agent' not found/)
      end
    end

    context 'when target agent task execution raises an error' do
      let(:target_error) { StandardError.new('Target agent failed!') }
      before do
        # Stub definition store to return the definition, expect string name
        allow(ADK::AgentDefinitionStore).to receive(:find).with(target_agent_name.to_s).and_return(target_definition_hash)
        # Stub run_task to raise error
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

    context 'when context does not provide a valid tool registry' do
      let(:invalid_context) { instance_double(ADK::ToolContext, tool_registry: nil, to_h: {}) }
      before do
        # Definition needs to be found for this test
        allow(ADK::AgentDefinitionStore).to receive(:find).with(target_agent_name.to_s).and_return(target_definition_hash)
      end

      it 'raises ToolError' do
        expect {
          tool.execute(params, invalid_context)
        }.to raise_error(ADK::ToolError, /Tool registry not found or invalid/)
      end
    end

    context 'when target agent definition has no tools listed' do
      let(:definition_no_tools) { target_definition_hash.merge(tools: []) }
      before do
        allow(ADK::AgentDefinitionStore).to receive(:find).with(target_agent_name.to_s).and_return(definition_no_tools)
        # Ensure agent mock doesn't expect tool registration
        allow(mock_target_agent).to receive(:register_tool_class) # Allow 0 calls
      end

      it 'warns but proceeds successfully' do
        expect(ADK.logger).to receive(:warn).with(/Target agent 'calculator_agent' has no tools configured/)
        expect(mock_target_agent).not_to receive(:register_tool_class) # Verify no registration attempts

        result = tool.execute(params, mock_context)
        expect(result[:status]).to eq(:success) # Should still succeed, just with no tools
      end
    end

    context 'when a needed tool is not found in the executing registry' do
      let(:definition_missing_tool) { target_definition_hash.merge(tools: %w[calculator missing_tool]) }
      before do
        allow(ADK::AgentDefinitionStore).to receive(:find).with(target_agent_name.to_s).and_return(definition_missing_tool)
        # Make executing registry return nil for the missing tool
        allow(mock_executing_registry).to receive(:find_class).with(:calculator).and_return(ADK::Tools::Calculator)
        allow(mock_executing_registry).to receive(:find_class).with(:missing_tool).and_return(nil)
      end

      it 'warns about the missing tool but continues with found tools' do
        expect(ADK.logger).to receive(:warn).with(/Tool 'missing_tool'.*not found.*Skipping/)
        expect(mock_target_agent).to receive(:register_tool_class).with(ADK::Tools::Calculator) # Register found tool
        expect(mock_target_agent).not_to receive(:register_tool_class).with(nil) # Don't register nil

        result = tool.execute(params, mock_context)
        expect(result[:status]).to eq(:success) # Execution proceeds
      end
    end

    context 'with missing parameters (base validation)' do
      it 'raises ADK::ToolArgumentError if target_agent_name is missing' do
        bad_params = { task: task_to_delegate } # Missing target_agent_name
        expect {
          tool.execute(bad_params, mock_context)
        }.to raise_error(ADK::ToolArgumentError, /Missing required parameters: target_agent_name/)
      end

      it 'raises ADK::ToolArgumentError if task is missing' do
        bad_params = { target_agent_name: target_agent_name.to_s } # Missing task
        expect {
          tool.execute(bad_params, mock_context)
        }.to raise_error(ADK::ToolArgumentError, /Missing required parameters: task/)
      end
    end
  end
end
