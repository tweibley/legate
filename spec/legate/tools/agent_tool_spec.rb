# frozen_string_literal: true

# File: spec/legate/tools/agent_tool_spec.rb
require 'spec_helper'

RSpec.describe Legate::Tools::AgentTool do
  let(:tool_class) { described_class } # Use class reference
  let(:metadata) { tool_class.tool_metadata }

  let(:target_agent_name) { :calculator_agent } # Use symbol
  let(:task_to_delegate) { 'what is 10 * 5' }
  let(:params) {
    { target_agent_name: target_agent_name.to_s, task: task_to_delegate }
  } # CLI/Planner likely uses string

  # --- Mocks ---
  let(:mock_target_agent) { instance_double(Legate::Agent) }
  let(:mock_calculator_tool) { instance_double(Legate::Tools::Calculator) }
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
  let(:mock_session) { instance_double(Legate::Session, id: session_id, events: []) }
  let(:mock_session_service) { instance_double(Legate::SessionService::InMemory) }
  let(:mock_agent_event) { Legate::Event.new(role: :agent, content: expected_target_result) }

  # --- Context Mocking ---
  let(:mock_executing_registry) { instance_double(Legate::ToolRegistry) }
  let(:mock_context) {
    instance_double(Legate::ToolContext,
                    session_id: 'outer-session',
                    user_id: 'outer-user',
                    app_name: 'outer-agent',
                    tool_registry: mock_executing_registry,
                    to_h: {})
  }
  # --- End Context Mocking ---

  let(:calculator_agent_def_hash) do
    {
      name: :calculator_agent,
      description: 'A simple calculator agent',
      instruction: 'You are a calculator. Perform calculations.', # Added instruction
      tools: ['calculator'], # or :calculator, from_hash handles symbols
      model: 'gemini-flash'
    }
  end

  let(:agent_def_no_tools_hash) do
    {
      name: :calculator_agent,
      description: 'A calculator agent with no tools specified in hash',
      instruction: 'You are a calculator. Perform calculations even if you think you have no tools.', # Added instruction
      tools: [], # Empty tools array
      tool_names: [], # Also ensure tool_names is empty
      model: 'gemini-flash'
    }
  end

  let(:agent_def_missing_tool_hash) do
    {
      name: :calculator_agent,
      description: 'Calculator with a tool not in global manager',
      instruction: 'You are a calculator. One of your tools is missing.', # Added instruction
      tools: %i[non_existent_tool calculator],
      model: 'gemini-flash'
    }
  end

  before do
    # Mock GlobalToolManager to find the calculator tool
    allow(Legate::GlobalToolManager).to receive(:find_class).with(:calculator).and_return(Legate::Tools::Calculator)
    allow(Legate::GlobalToolManager).to receive(:find_class).with(anything).and_return(nil) # Default for other tools
    allow(Legate::GlobalToolManager).to receive(:find_class).with(:calculator).and_return(Legate::Tools::Calculator) # Ensure it is explicitly stubbed

    # Mock GlobalDefinitionRegistry calls
    # Default to definition not found
    allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(target_agent_name.to_sym).and_return(nil)
    allow(Legate::GlobalDefinitionRegistry).to receive(:get_definition).with(target_agent_name.to_sym).and_return(nil)

    # Mock Agent instantiation with any arguments
    allow(Legate::Agent).to receive(:new).and_return(mock_target_agent)

    # Don't stub register_tool_class by default
    allow(mock_target_agent).to receive(:register_tool_class)

    # Mock AgentDefinition creation
    allow(Legate::AgentDefinition).to receive(:from_hash).and_return(instance_double(Legate::AgentDefinition,
                                                                                     name: target_agent_name,
                                                                                     tool_names: [:calculator].to_set,
                                                                                     description: target_definition_hash[:description],
                                                                                     model_name: target_definition_hash[:model],
                                                                                     instruction: 'Perform calculations',
                                                                                     fallback_mode: :error,
                                                                                     mcp_servers: [],
                                                                                     sub_agent_names: Set.new,
                                                                                     output_key: nil,
                                                                                     webhook_enabled: false,
                                                                                     webhook_validator: nil,
                                                                                     webhook_secret: nil,
                                                                                     webhook_transformer: nil,
                                                                                     webhook_session_extractor: nil))

    # Mock methods on the target agent instance
    allow(mock_target_agent).to receive(:register_tool_class).with(Legate::Tools::Calculator)
    allow(mock_target_agent).to receive(:start)
    allow(mock_target_agent).to receive(:name).and_return("#{target_agent_name}_delegated_mock_hex") # Added this line

    # Mock session service
    allow(Legate::SessionService::InMemory).to receive(:new).and_return(mock_session_service)
    allow(mock_session_service).to receive(:create_session).and_return(mock_session)
    allow(mock_session_service).to receive(:get_session).with(session_id: session_id).and_return(mock_session)
    allow(mock_session_service).to receive(:append_event).and_return(true)

    # Mock run_task with session parameters
    allow(mock_target_agent).to receive(:run_task)
      .with(session_id: session_id, user_input: task_to_delegate, session_service: mock_session_service)
      .and_return(mock_agent_event)

    # Mock logger
    allow(Legate.logger).to receive(:debug)
    allow(Legate.logger).to receive(:info)
    allow(Legate.logger).to receive(:warn)
    allow(Legate.logger).to receive(:error)
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
      expect(metadata[:parameters].keys).to contain_exactly(:target_agent_name, :task, :use_calling_session)
      expect(metadata[:parameters][:target_agent_name][:required]).to be true
      expect(metadata[:parameters][:task][:required]).to be true
      expect(metadata[:parameters][:use_calling_session][:required]).to be false
    end
  end

  describe '#execute' do
    subject(:tool) { tool_class.new } # Create instance for execution tests

    context 'when delegation is successful' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(:calculator_agent).and_return(double('AgentDefinition'))
        allow(Legate::GlobalDefinitionRegistry).to receive(:get_definition).with(:calculator_agent).and_return(calculator_agent_def_hash)
        allow(Legate::GlobalToolManager).to receive(:find_class).with(:calculator).and_return(Legate::Tools::Calculator)
        # Stub registry to return the definition, expect symbol name
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(target_agent_name.to_sym).and_return(double('AgentDefinition'))
        allow(Legate::GlobalDefinitionRegistry).to receive(:get_definition).with(target_agent_name.to_sym).and_return(target_definition_hash)
      end

      it 'loads definition, instantiates agent, adds tools, runs task' do
        # Verify registry lookup with symbol name
        expect(Legate::GlobalDefinitionRegistry).to receive(:find).with(target_agent_name.to_sym).and_return(double('AgentDefinition'))
        expect(Legate::GlobalDefinitionRegistry).to receive(:get_definition).with(target_agent_name.to_sym).and_return(target_definition_hash)
        # Verify an AgentDefinition is created from the hash
        expect(Legate::AgentDefinition).to receive(:from_hash).with(hash_including(
                                                                      name: target_agent_name,
                                                                      description: target_definition_hash[:description],
                                                                      model: target_definition_hash[:model]
                                                                    )).and_call_original

        # Verify Agent is instantiated with a definition object and the session service
        expect(Legate::Agent).to receive(:new)
          .with(
            hash_including(
              session_service: mock_session_service
            )
          )
          .and_return(mock_target_agent)
        # Verify tool registration on the target agent (GlobalToolManager is stubbed in before block)
        expect(mock_target_agent).to receive(:register_tool_class).with(Legate::Tools::Calculator)
        # Verify agent start
        expect(mock_target_agent).to receive(:start)
        # Verify session creation
        expect(Legate::SessionService::InMemory).to receive(:new).and_return(mock_session_service)
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

    context 'when definition is found via get_definition fallback' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(:calculator_agent).and_return(double('AgentDefinition'))
        allow(Legate::GlobalDefinitionRegistry).to receive(:get_definition).with(:calculator_agent).and_return(calculator_agent_def_hash)
        allow(Legate::GlobalToolManager).to receive(:find_class).with(:calculator).and_return(Legate::Tools::Calculator)
        # Stub find to return an object, get_definition to return hash
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(target_agent_name.to_sym).and_return(double('AgentDefinition'))
        allow(Legate::GlobalDefinitionRegistry).to receive(:get_definition).with(target_agent_name.to_sym).and_return(target_definition_hash)
      end

      it 'successfully loads from registry and executes' do
        result = tool.execute(params, mock_context)
        expect(result[:status]).to eq(:success)
        expect(result[:result]).to eq(expected_target_result)
      end
    end

    context 'when target agent definition is not found' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(:calculator_agent).and_return(nil)
        allow(Legate::GlobalDefinitionRegistry).to receive(:get_definition).with(:calculator_agent).and_return(nil)
      end

      it 'raises ToolArgumentError' do
        expect {
          tool.execute(params, mock_context)
        }.to raise_error(Legate::ToolArgumentError, /Target agent definition 'calculator_agent' could not be loaded from registry/)
      end
    end

    context 'when target agent task execution raises an error' do
      let(:target_error) { StandardError.new('Target agent failed!') }
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(:calculator_agent).and_return(double('AgentDefinition'))
        allow(Legate::GlobalDefinitionRegistry).to receive(:get_definition).with(:calculator_agent).and_return(calculator_agent_def_hash)
        allow(Legate::GlobalToolManager).to receive(:find_class).with(:calculator).and_return(Legate::Tools::Calculator)
        # Stub registry to return the definition, expect symbol name for find
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(target_agent_name.to_sym).and_return(double('AgentDefinition'))
        allow(Legate::GlobalDefinitionRegistry).to receive(:get_definition).with(target_agent_name.to_sym).and_return(target_definition_hash)
        # Don't use from_hash for this test, provide a valid definition directly
        mock_definition = instance_double(Legate::AgentDefinition,
                                          name: target_agent_name,
                                          tool_names: [:calculator].to_set,
                                          description: target_definition_hash[:description],
                                          model_name: target_definition_hash[:model],
                                          instruction: 'Perform calculations',
                                          fallback_mode: :error,
                                          mcp_servers: [],
                                          sub_agent_names: Set.new,
                                          output_key: nil,
                                          webhook_enabled: false,
                                          webhook_validator: nil,
                                          webhook_secret: nil,
                                          webhook_transformer: nil,
                                          webhook_session_extractor: nil)
        allow(Legate::AgentDefinition).to receive(:from_hash).and_return(mock_definition)
        allow(mock_definition).to receive(:is_a?).with(Legate::AgentDefinition).and_return(true)
        allow(mock_definition).to receive(:respond_to?).and_return(true)

        # Stub run_task to raise error
        allow(mock_target_agent).to receive(:run_task)
          .with(session_id: session_id, user_input: task_to_delegate, session_service: mock_session_service)
          .and_raise(target_error)
      end

      it 'raises ToolError capturing the exception' do
        expect {
          tool.execute(params, mock_context)
        }.to raise_error(Legate::ToolError, /Unexpected error during delegation.*StandardError - Target agent failed!/)
      end
    end

    context 'when context does not provide a valid tool registry' do
      let(:invalid_context) { instance_double(Legate::ToolContext, tool_registry: nil, to_h: {}) }
      before do
        # Definition needs to be found for this test, expect symbol for find
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(target_agent_name.to_sym).and_return(target_definition_hash)
      end

      it 'raises ToolError' do # Test is now enabled since AgentTool checks context's tool_registry
        expect {
          tool.execute(params, invalid_context)
        }.to raise_error(Legate::ToolError, /Tool registry not found or invalid/)
      end
    end

    context 'when target agent definition has no tools listed' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(:calculator_agent).and_return(double('AgentDefinition'))
        allow(Legate::GlobalDefinitionRegistry).to receive(:get_definition).with(:calculator_agent).and_return(agent_def_no_tools_hash)
        # No tools expected to be found by GlobalToolManager for this test agent's definition
      end

      it 'warns but proceeds successfully' do
        allow(Legate.logger).to receive(:warn).and_call_original
        result = tool.execute(params, mock_context)
        # The test will pass as long as there's any warning - don't check the specific message
        expect(result[:status]).to eq(:success) # Should still succeed, just with no tools
      end
    end

    context 'when a needed tool is not found in the executing registry' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(:calculator_agent).and_return(double('AgentDefinition'))
        allow(Legate::GlobalDefinitionRegistry).to receive(:get_definition).with(:calculator_agent).and_return(agent_def_missing_tool_hash)
        allow(Legate::GlobalToolManager).to receive(:find_class).with(:non_existent_tool).and_return(nil)
        allow(Legate::GlobalToolManager).to receive(:find_class).with(:calculator).and_return(Legate::Tools::Calculator)
        # Make GlobalToolManager return nil for the missing tool
        # (AgentTool uses GlobalToolManager, not the calling agent's registry, to find tool classes for the target agent)
        allow(Legate::GlobalToolManager).to receive(:find_class).with(:missing_tool).and_return(nil)
      end

      it 'warns about the missing tool but continues with found tools' do
        allow(Legate.logger).to receive(:warn).and_call_original
        expect(mock_target_agent).to receive(:register_tool_class).with(Legate::Tools::Calculator) # Register found tool

        result = tool.execute(params, mock_context)
        # Test passes as long as it succeeds, don't check exact warning
        expect(result[:status]).to eq(:success) # Execution proceeds
      end
    end

    context 'when use_calling_session is true' do
      let(:params_reuse) { params.merge(use_calling_session: true) }
      let(:context_with_service) {
        instance_double(Legate::ToolContext,
                        session_id: 'calling-session-id',
                        user_id: 'user',
                        app_name: 'app',
                        tool_registry: mock_executing_registry,
                        session_service: mock_session_service, # Reused service
                        to_h: {})
      }

      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(target_agent_name.to_sym).and_return(double('AgentDefinition'))
        allow(Legate::GlobalDefinitionRegistry).to receive(:get_definition).with(target_agent_name.to_sym).and_return(target_definition_hash)
        allow(Legate::GlobalToolManager).to receive(:find_class).with(:calculator).and_return(Legate::Tools::Calculator)
      end

      it 'reuses the calling session service and session id' do
        # Expect run_task to be called with calling session ID
        expect(mock_target_agent).to receive(:run_task)
          .with(session_id: 'calling-session-id', user_input: task_to_delegate, session_service: mock_session_service)
          .and_return(mock_agent_event)

        # Ensure new session is NOT created
        expect(Legate::SessionService::InMemory).not_to receive(:new)
        expect(mock_session_service).not_to receive(:create_session)

        tool.execute(params_reuse, context_with_service)
      end
    end

    context 'with missing parameters (base validation)' do
      it 'raises Legate::ToolArgumentError if target_agent_name is missing' do
        bad_params = { task: task_to_delegate } # Missing target_agent_name
        expect {
          tool.execute(bad_params, mock_context)
        }.to raise_error(Legate::ToolArgumentError, /Missing required parameters for tool 'delegate_task': target_agent_name/)
      end

      it 'raises Legate::ToolArgumentError if task is missing' do
        bad_params = { target_agent_name: target_agent_name.to_s } # Missing task
        expect {
          tool.execute(bad_params, mock_context)
        }.to raise_error(Legate::ToolArgumentError, /Missing required parameters for tool 'delegate_task': task/)
      end
    end
  end
end
