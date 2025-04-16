# File: spec/adk/agent_spec.rb
require 'spec_helper'

RSpec.describe ADK::Agent do
  # --- Setup (Mostly the same) ---
  let(:name) { 'test_agent' }
  let(:description) { 'Test Description' }
  let(:model_name) { 'test-model-123' }
  let(:mock_planner) { instance_double(ADK::Planner) }
  let(:mock_memory) { instance_double(ADK::Memory) }
  let(:mock_session) { instance_double(ADK::Session) }
  let(:mock_logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }

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

  let(:options) { { planner: mock_planner, memory: mock_memory, session: mock_session, logger: mock_logger } }
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
        memory: mock_memory,
        session: mock_session,
        logger: mock_logger
      )
      expect(default_agent.model_name).to eq(ADK::Agent::DEFAULT_MODEL)
    end

    it 'initializes with empty tools array' do
      expect(agent.tools).to be_empty
    end

    it 'initializes with provided dependencies' do
      expect(agent.planner).to eq(mock_planner)
      expect(agent.memory).to eq(mock_memory)
      expect(agent.session).to eq(mock_session)
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
        result = agent.run_task(task)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include("not running")
      end

      it 'calls planner.plan with the task' do
        agent.start
        expect(mock_planner).to receive(:plan).with(task).and_return(single_step_plan)
        agent.run_task(task)
      end

      it 'calls the correct tool execute method' do
        agent.start
        # Verify the underlying tool's execute was called via execute_step/execute_plan
        expect(mock_tool_a).to receive(:execute).with({ arg: 'value' }).and_return(single_step_success_result)
        agent.run_task(task)
      end

      it 'returns the result from execute_plan (single step)' do
        agent.start
        result = agent.run_task(task)
        expect(result).to eq(single_step_success_result)
      end

      it 'returns array of results for multi-step plan' do
        agent.start
        multi_step_plan = [
          { tool: :tool_a, params: { arg: 'step1' } },
          { tool: :tool_b, params: { arg: 'step2' } }
        ]
        result_a = { status: :success, result: 'Done A Multi' }
        result_b = { status: :success, result: 'Done B Multi' }
        allow(mock_planner).to receive(:plan).with(task).and_return(multi_step_plan)
        allow(mock_tool_a).to receive(:execute).with({ arg: 'step1' }).and_return(result_a)
        allow(mock_tool_b).to receive(:execute).with({ arg: 'step2' }).and_return(result_b) # Note: No injection tested here yet

        result = agent.run_task(task)
        expect(result).to eq([result_a, result_b])
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
        agent.run_task(task)
      end

      it 'injects nested success result (from AgentTool) into the next step' do
        plan_with_agent_tool = [{ tool: :delegate_task, params: step1_params },
                                { tool: step2_tool, params: step2_params_placeholder }]
        allow(mock_planner).to receive(:plan).with(task).and_return(plan_with_agent_tool)
        allow(mock_agent_tool).to receive(:execute).with(step1_params).and_return(step1_result_nested)

        # Expect tool B to be called with the *inner* injected result
        expect(mock_tool_b).to receive(:execute).with({ input: 'Inner Value' }).and_return(step2_result_success)
        agent.run_task(task)
      end

      it 'does NOT inject if previous step failed' do
        allow(mock_tool_a).to receive(:execute).with(step1_params).and_return(step1_result_error)
        # Expect tool B to be called with the *original placeholder*
        expect(mock_tool_b).to receive(:execute).with({ input: '[Result from step 1]' }).and_return(step2_result_success)
        agent.run_task(task)
      end

      it 'does NOT inject if previous step succeeded but lacked :result key' do
        allow(mock_tool_a).to receive(:execute).with(step1_params).and_return(step1_result_no_key)
        # Expect tool B to be called with the *original placeholder*
        expect(mock_tool_b).to receive(:execute).with({ input: '[Result from step 1]' }).and_return(step2_result_success)
        agent.run_task(task)
      end

      it 'does NOT modify parameters without placeholders' do
        plan_no_placeholder = [{ tool: step1_tool, params: step1_params },
                               { tool: step2_tool, params: step2_params_no_placeholder }]
        allow(mock_planner).to receive(:plan).with(task).and_return(plan_no_placeholder)
        allow(mock_tool_a).to receive(:execute).with(step1_params).and_return(step1_result_simple)

        # Expect tool B to be called with its original static params
        expect(mock_tool_b).to receive(:execute).with({ input: 'Static Value' }).and_return(step2_result_success)
        agent.run_task(task)
      end
    end # End Context Result Injection

    # --- Existing tests for planner/execution failure ---
    context 'when planner fails' do
      before do
        agent.start
        allow(mock_planner).to receive(:plan).and_raise(StandardError.new("Planner boom"))
      end

      it 'returns an error hash' do
        result = agent.run_task(task)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include("Planner boom")
      end
    end

    context 'when execute_step fails (e.g., tool not found)' do
      before do
        agent.start
        # Simulate a plan with a tool not added to the agent
        plan_bad_tool = [{ tool: :non_existent_tool, params: {} }]
        allow(mock_planner).to receive(:plan).with(task).and_return(plan_bad_tool)
        # Don't need to mock execute_step itself, let it try and fail
      end

      it 'returns an error hash from execute_step' do
        result = agent.run_task(task)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include("Tool 'non_existent_tool' not found")
      end
    end

    context 'when tool execute raises validation error' do
      before do
        agent.start
        plan_bad_params = [{ tool: :tool_a, params: {} }] # Missing required param if tool_a needs one
        allow(mock_planner).to receive(:plan).with(task).and_return(plan_bad_params)
        # Make the tool's execute raise the error
        allow(mock_tool_a).to receive(:execute).with({}).and_raise(ADK::Error.new("Missing required parameters: some_param"))
      end

      it 'returns the error hash from execute_step' do
        result = agent.run_task(task)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to eq("Missing required parameters: some_param")
      end
    end
    # --- End existing failure tests ---
  end # End describe #run_task
end
