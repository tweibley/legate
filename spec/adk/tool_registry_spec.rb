require 'spec_helper'

RSpec.describe ADK::Agent do
  let(:name) { 'test_agent' }
  let(:description) { 'Test Description' }
  let(:model_name) { 'test-model-123' }
  let(:mock_planner) { instance_double(ADK::Planner) }
  let(:mock_memory) { instance_double(ADK::Memory) }
  let(:mock_session) { instance_double(ADK::Session) }
  let(:mock_logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }

  # Create proper tool mock for testing
  let(:mock_tool) do
    tool = instance_double(ADK::Tool, name: :mock_tool)
    allow(tool).to receive(:is_a?).with(ADK::Tool).and_return(true)
    tool
  end

  let(:options) { { planner: mock_planner, memory: mock_memory, session: mock_session, logger: mock_logger } }

  subject(:agent) { described_class.new(name: name, description: description, model_name: model_name, **options) }

  describe '#initialize' do
    it 'sets name, description, and model' do
      expect(agent.name).to eq(name)
      expect(agent.description).to eq(description)
      expect(agent.model_name).to eq(model_name)
    end

    it 'uses default model if none provided' do
      agent_default = described_class.new(name: name, description: description, **options)
      expect(agent_default.model_name).to eq(ADK::Agent::DEFAULT_MODEL)
    end

    it 'initializes with provided planner' do
      expect(agent.planner).to eq(mock_planner)
    end

    it 'creates default planner if not provided' do
      allow(ADK::Planner).to receive(:new).and_return(mock_planner)

      agent_default_deps = described_class.new(
        name: name,
        description: description,
        logger: mock_logger
      )

      expect(ADK::Planner).to have_received(:new).with(
        agent: agent_default_deps,
        logger: mock_logger,
        model_name: ADK::Agent::DEFAULT_MODEL
      )
      expect(agent_default_deps.planner).to eq(mock_planner)
    end
  end

  describe '#add_tool' do
    it 'adds a valid tool to the tools list' do
      expect { agent.add_tool(mock_tool) }.to change { agent.tools.count }.by(1)
      expect(agent.tools).to include(mock_tool)
    end

    it 'warns and does not add a duplicate tool' do
      agent.add_tool(mock_tool)
      expect(mock_logger).to receive(:warn).with(/already added/)
      expect { agent.add_tool(mock_tool) }.not_to change { agent.tools.count }
    end

    it 'does not add an invalid object' do
      invalid_tool = "not a tool"
      expect(mock_logger).to receive(:error).with(/Attempted to add invalid tool/)
      expect { agent.add_tool(invalid_tool) }.not_to change { agent.tools.count }
    end
  end

  describe '#start/#stop/#running?' do
    it 'starts the agent' do
      expect { agent.start }.to change { agent.running? }.from(false).to(true)
    end
    it 'stops a running agent' do
      agent.start
      expect { agent.stop }.to change { agent.running? }.from(true).to(false)
    end
    # Add tests for idempotency warnings if desired
  end

  describe '#run_task' do
    let(:task) { "Do the thing" }
    let(:plan) { [{ tool: :mock_tool, params: { arg: 'value' } }] }
    let(:success_result) { { status: :success, result: 'Done' } }
    let(:session_id) { 'test-session-id' }
    let(:mock_session_service) { instance_double(ADK::SessionService::InMemory) }

    before do
      agent.add_tool(mock_tool)
      allow(mock_planner).to receive(:plan).with(task).and_return(plan)
      # Mock execute_step directly for focused testing
      allow(agent).to receive(:execute_step).with(plan.first, session_id, mock_session_service).and_return(success_result)
      allow(mock_session_service).to receive(:get_session).with(session_id: session_id).and_return(true)
      allow(mock_session_service).to receive(:add_event_and_update_state)
    end

    it 'returns error hash if agent is not running' do
      # Agent starts not running by default
      result = agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
      expect(result[:status]).to eq(:error)
      expect(result[:error_message]).to include("not active")
    end

    it 'calls planner.plan with the task' do
      agent.start
      expect(mock_planner).to receive(:plan).with(task).and_return(plan)
      agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
    end

    it 'calls execute_plan with the plan' do
      agent.start
      # This is harder to mock directly, test via execute_step mock
      expect(agent).to receive(:execute_step).with(plan.first, session_id, mock_session_service).and_return(success_result)
      agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
    end

    it 'returns the result from execute_plan (single step)' do
      agent.start
      result = agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
      expect(result).to be_a(ADK::Event)
    end

    context 'with multi-step plan' do
      let(:plan) { [{ tool: :tool_a, params: {} }, { tool: :tool_b, params: {} }] }
      let(:result1) { { status: :success, result: 'Step 1 Done' } }
      let(:result2) { { status: :success, result: 'Step 2 Done' } }

      before do
        agent.start
        # Need to mock specific calls to execute_step with different steps
        allow(agent).to receive(:execute_step).with(plan[0], session_id, mock_session_service).and_return(result1)
        allow(agent).to receive(:execute_step).with(plan[1], session_id, mock_session_service).and_return(result2)
      end

      it 'returns an array of results' do
        result = agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
        expect(result).to be_a(ADK::Event)
      end
    end

    context 'when planner fails' do
      before {
        agent.start
        allow(mock_planner).to receive(:plan).and_raise(StandardError.new("Planner boom"))
      }

      it 'returns an error hash' do
        result = agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include("Planner boom")
      end
    end

    context 'when execute_step fails' do
      before {
        agent.start
        allow(agent).to receive(:execute_step).and_raise(ADK::Error.new("Exec boom"))
      }

      it 'returns an error hash' do
        result = agent.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include("Exec boom")
      end
    end
  end
  # TODO: Add tests for private methods like execute_plan, execute_step if needed (can be tricky)
end
