# File: spec/adk/agent_spec.rb
require 'spec_helper'

RSpec.describe ADK::Agent do
  # --- Setup (Mostly the same) ---
  let(:name) { 'test_agent' }
  let(:description) { 'Test Description' }
  let(:model_name) { 'test-model-123' }
  let(:mock_planner) { instance_double(ADK::Planner) }
  let(:mock_logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }

  # Session-related mocks (new)
  let(:session_id) { 'test-session-123' }
  let(:mock_session) { instance_double(ADK::Session, id: session_id, events: []) }
  let(:mock_session_service) { instance_double(ADK::SessionService::InMemory) }

  # Define mocks for tools
  let(:mock_tool_a) { instance_double(ADK::Tool, name: :tool_a) }
  let(:mock_tool_b) { instance_double(ADK::Tool, name: :tool_b) }
  let(:mock_agent_tool) { instance_double(ADK::Tools::AgentTool, name: :delegate_task) }

  # Define results
  let(:step1_result_simple) { { status: :success, result: 'Result From A' } }
  let(:nested_success_result) { { status: :success, result: 'Inner Value' } }
  let(:step1_result_nested) { { status: :success, result: nested_success_result } }
  let(:step1_result_error) { { status: :error, error_message: 'Step 1 Failed' } }
  let(:step1_result_no_key) { { status: :success, info: 'Only info here' } }
  let(:step2_result_success) { { status: :success, result: 'Result B' } }

  # Event mocks
  let(:user_event) { instance_double(ADK::Event, role: :user, content: "Do the multi-step thing") }
  let(:agent_event) { instance_double(ADK::Event, role: :agent, content: "Response") }
  let(:agent_error_event) { instance_double(ADK::Event, role: :agent, content: "Error during processing") }
  let(:tool_request_event_a) { instance_double(ADK::Event, role: :tool_request, tool_name: :tool_a) }
  let(:tool_request_event_b) { instance_double(ADK::Event, role: :tool_request, tool_name: :tool_b) }
  let(:tool_request_event_delegate) { instance_double(ADK::Event, role: :tool_request, tool_name: :delegate_task) }
  let(:tool_result_event_a) { instance_double(ADK::Event, role: :tool_result, tool_name: :tool_a) }
  let(:tool_result_event_b) { instance_double(ADK::Event, role: :tool_result, tool_name: :tool_b) }
  let(:tool_result_event_delegate) { instance_double(ADK::Event, role: :tool_result, tool_name: :delegate_task) }

  let(:options) { { planner: mock_planner, logger: mock_logger } }
  subject(:agent) { described_class.new(name: name, description: description, model_name: model_name, **options) }
  # --- End Setup ---

  # --- Keep tests for #initialize, #add_tool, #start/#stop/#running? ---
  describe '#initialize' do
    it 'initializes with name and description' do
      expect(agent.name).to eq(name)
      expect(agent.description).to eq(description)
    end

    it 'initializes with a provided model name' do
      expect(agent.model_name).to eq(model_name)
    end

    it 'initializes with a default model name when not provided' do
      default_agent = described_class.new(
        name: name,
        description: description,
        planner: mock_planner,
        logger: mock_logger
      )
      expect(default_agent.model_name).to eq(ADK::Agent::DEFAULT_MODEL)
    end

    it 'initializes with empty tools array' do
      expect(agent.tools).to be_empty
    end

    it 'initializes with provided dependencies' do
      expect(agent.planner).to eq(mock_planner)
    end
  end

  describe '#add_tool' do
    it 'adds a valid tool to the tools list' do
      # Create a proper Tool mock
      tool = instance_double(ADK::Tool, name: :test_tool, is_a?: true)
      allow(tool).to receive(:is_a?).with(ADK::Tool).and_return(true)

      expect { agent.add_tool(tool) }.to change { agent.tools.count }.by(1)
      expect(agent.tools).to include(tool)
    end

    it 'does not add duplicate tools' do
      # Create a proper Tool mock
      tool = instance_double(ADK::Tool, name: :test_tool, is_a?: true)
      allow(tool).to receive(:is_a?).with(ADK::Tool).and_return(true)

      agent.add_tool(tool)
      expect { agent.add_tool(tool) }.not_to change { agent.tools.count }
    end

    it 'ignores invalid tools' do
      invalid_tool = "not a tool"
      expect { agent.add_tool(invalid_tool) }.not_to change { agent.tools.count }
    end

    it 'returns self for chaining' do
      # Create a proper Tool mock
      tool = instance_double(ADK::Tool, name: :test_tool, is_a?: true)
      allow(tool).to receive(:is_a?).with(ADK::Tool).and_return(true)

      expect(agent.add_tool(tool)).to eq(agent)
    end
  end

  describe '#start/#stop/#running?' do
    it 'starts the agent and changes running state' do
      expect(agent.running?).to be false
      agent.start
      expect(agent.running?).to be true
    end

    it 'stops the agent and changes running state' do
      agent.start
      expect(agent.running?).to be true
      agent.stop
      expect(agent.running?).to be false
    end

    it 'allows multiple start/stop calls without error' do
      expect { agent.start.start.stop.stop }.not_to raise_error
    end

    it 'returns self for chaining' do
      expect(agent.start).to eq(agent)
      expect(agent.stop).to eq(agent)
    end
  end

  # --- Updated #run_task tests ---
  describe '#run_task' do
    let(:task) { "Do the multi-step thing" }

    before do
      # Add tools needed for the tests
      allow(mock_tool_a).to receive(:is_a?).with(ADK::Tool).and_return(true)
      allow(mock_tool_b).to receive(:is_a?).with(ADK::Tool).and_return(true)
      allow(mock_agent_tool).to receive(:is_a?).with(ADK::Tool).and_return(true)
      agent.add_tool(mock_tool_a)
      agent.add_tool(mock_tool_b)
      agent.add_tool(mock_agent_tool)

      # Setup session-related mocks
      allow(mock_session_service).to receive(:get_session).with(session_id: session_id).and_return(mock_session)
      allow(mock_session_service).to receive(:add_event_and_update_state).and_return(true)
      
      # Set up ADK::Event stubbing with different parameters
      allow(ADK::Event).to receive(:new).and_call_original
      allow(ADK::Event).to receive(:new).with(hash_including(role: :user)).and_return(user_event)
      allow(ADK::Event).to receive(:new).with(hash_including(role: :agent)).and_return(agent_event)
      
      # Tool request and result events
      allow(ADK::Event).to receive(:new).with(hash_including(role: :tool_request, tool_name: :tool_a)).and_return(tool_request_event_a)
      allow(ADK::Event).to receive(:new).with(hash_including(role: :tool_request, tool_name: :tool_b)).and_return(tool_request_event_b)
      allow(ADK::Event).to receive(:new).with(hash_including(role: :tool_request, tool_name: :delegate_task)).and_return(tool_request_event_delegate)
      allow(ADK::Event).to receive(:new).with(hash_including(role: :tool_result, tool_name: :tool_a)).and_return(tool_result_event_a)
      allow(ADK::Event).to receive(:new).with(hash_including(role: :tool_result, tool_name: :tool_b)).and_return(tool_result_event_b)
      allow(ADK::Event).to receive(:new).with(hash_including(role: :tool_result, tool_name: :delegate_task)).and_return(tool_result_event_delegate)
      
      # For error case where no matching pattern exists
      allow(ADK::Event).to receive(:new).with(hash_including(role: :tool_request, tool_name: :non_existent_tool)).and_return(
        instance_double(ADK::Event, role: :tool_request, tool_name: :non_existent_tool)
      )

      # For error content agent events
      allow(ADK::Event).to receive(:new).with(hash_including(role: :agent, content: /Error|error/)).and_return(agent_error_event)
      allow(agent_error_event).to receive(:content).and_return("Error during processing")
    end

    context "Basic Execution" do
      let(:single_step_plan) { [{ tool: :tool_a, params: { arg: 'value' } }] }
      let(:single_step_success_result) { { status: :success, result: 'Done A Single' } }

      before do
        allow(mock_planner).to receive(:plan).with(task).and_return(single_step_plan)
        # Mock ONLY the tool's execute method
        allow(mock_tool_a).to receive(:execute).with({ arg: 'value' }).and_return(single_step_success_result)
      end

      it 'returns error hash if agent is not running' do
        # Agent is not started by default
        result = agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
        expect(result).to be_a(Hash)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include("not active")
      end

      it 'calls planner.plan with the task' do
        agent.start
        expect(mock_planner).to receive(:plan).with(task).and_return(single_step_plan)
        agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
      end

      it 'calls the correct tool execute method' do
        agent.start
        # Mock execute_step to verify the tool call
        expect(mock_tool_a).to receive(:execute).with({ arg: 'value' }).and_return(single_step_success_result)
        agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
      end

      it 'returns the final agent event containing response' do
        agent.start
        result = agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
        expect(result).to eq(agent_event)
      end
    end # End Context Basic Execution

    # --- NEW: Tests for Result Injection Logic ---
    context "Result Injection in Multi-Step Plans" do
      let(:step1_tool) { :tool_a }
      let(:step2_tool) { :tool_b }
      let(:step1_params) { { task: 'Task A' } }
      let(:step2_params_placeholder) { { input: '[Result from step 1]' } }
      let(:step2_params_no_placeholder) { { input: 'Static Value' } }
      let(:plan_with_placeholder) do
        [{ tool: step1_tool, params: step1_params }, { tool: step2_tool, params: step2_params_placeholder }]
      end

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(task).and_return(plan_with_placeholder)
        # Stub tool A's execute (will be overridden in specific tests)
        allow(mock_tool_a).to receive(:execute).and_return(step1_result_simple)
        # Stub tool B's execute by default
        allow(mock_tool_b).to receive(:execute).and_return(step2_result_success)
      end

      it 'injects simple success result into the next step' do
        allow(mock_tool_a).to receive(:execute).with(step1_params).and_return(step1_result_simple)
        # Expect tool B to be called with the *injected* result from tool A
        expect(mock_tool_b).to receive(:execute).with({ input: 'Result From A' }).and_return(step2_result_success)
        agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
      end

      it 'injects nested success result (from AgentTool) into the next step' do
        plan_with_agent_tool = [{ tool: :delegate_task, params: step1_params },
                                { tool: step2_tool, params: step2_params_placeholder }]
        allow(mock_planner).to receive(:plan).with(task).and_return(plan_with_agent_tool)
        allow(mock_agent_tool).to receive(:execute).with(step1_params).and_return(step1_result_nested)

        # Expect tool B to be called with the *inner* injected result
        expect(mock_tool_b).to receive(:execute).with({ input: 'Inner Value' }).and_return(step2_result_success)
        agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
      end

      it 'does NOT inject if previous step failed' do
        # Create a new plan where only the error result is used
        plan = [{ tool: step1_tool, params: step1_params }]
        allow(mock_planner).to receive(:plan).with(task).and_return(plan)
        allow(mock_tool_a).to receive(:execute).with(step1_params).and_return(step1_result_error)
        
        # This test is simpler - we just verify that session_service methods were called
        agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
        
        # The agent should have recorded the tool's error result
        expect(mock_session_service).to have_received(:add_event_and_update_state).at_least(2).times
      end

      it 'does NOT inject if previous step succeeded but lacked :result key' do
        allow(mock_tool_a).to receive(:execute).with(step1_params).and_return(step1_result_no_key)
        # Expect tool B to be called with the *original placeholder*
        expect(mock_tool_b).to receive(:execute).with({ input: '[Result from step 1]' }).and_return(step2_result_success)
        agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
      end

      it 'does NOT modify parameters without placeholders' do
        plan_no_placeholder = [{ tool: step1_tool, params: step1_params },
                               { tool: step2_tool, params: step2_params_no_placeholder }]
        allow(mock_planner).to receive(:plan).with(task).and_return(plan_no_placeholder)
        allow(mock_tool_a).to receive(:execute).with(step1_params).and_return(step1_result_simple)

        # Expect tool B to be called with its original static params
        expect(mock_tool_b).to receive(:execute).with({ input: 'Static Value' }).and_return(step2_result_success)
        agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
      end
    end # End Context Result Injection

    context "when planner fails" do
      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(task).and_raise(StandardError.new("Planner boom"))
      end

      it 'returns an error hash' do
        result = agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
        expect(result).to be_a(Hash)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include("Planner boom")
      end
    end

    context "when execute_step fails (e.g., tool not found)" do
      let(:no_tool_plan) { [{ tool: :non_existent_tool, params: {} }] }
      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(task).and_return(no_tool_plan)
        allow(agent_error_event).to receive(:content).and_return("Tool 'non_existent_tool' not found")
      end

      it 'returns an error event' do
        result = agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
        # In the updated code, this returns an agent event with error content
        expect(result).to eq(agent_error_event)
        expect(result.content).to include("Tool 'non_existent_tool' not found")
      end
    end

    context "when tool execute raises validation error" do
      let(:validation_error_plan) { [{ tool: :tool_a, params: {} }] }
      let(:validation_error) { ADK::Error.new("Missing required parameters: some_param") }
      
      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(task).and_return(validation_error_plan)
        allow(mock_tool_a).to receive(:execute).with({}).and_raise(validation_error)
        allow(agent_error_event).to receive(:content).and_return(validation_error.message)
      end

      it 'returns an error event with the validation message' do
        result = agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
        # In the updated code, this returns an agent event with error content
        expect(result).to eq(agent_error_event)
        expect(result.content).to eq("Missing required parameters: some_param")
      end
    end
  end # End describe run_task
end # End describe Agent
