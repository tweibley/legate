# frozen_string_literal: true

require 'spec_helper'

# --- Mock Tool Classes for Testing Agent in this spec ---
class MockToolForAgent < ADK::Tool
  define_metadata(name: :mock_tool, description: 'Mock Tool', parameters: {})
  def perform_execution(params, context); { status: :success, result: 'mocked' }; end
end

class AnotherMockTool < ADK::Tool
  define_metadata(name: :another_tool, description: 'Another Mock Tool', parameters: {})
  def perform_execution(params, context); { status: :success, result: 'another' }; end
end
# --- End Mock Tool Classes ---

RSpec.describe ADK::Agent do # Testing Agent behavior here
  let(:name) { 'test_agent' }
  let(:description) { 'Test Description' }
  let(:model_name) { 'test-model-123' }
  let(:mock_planner) { instance_double(ADK::Planner) }

  # Tool instances (for mocking execute in run_task)
  let(:mock_tool_instance) {
    instance_double(MockToolForAgent, name: :mock_tool, execute: { status: :success, result: 'mocked' })
  }

  # --- Agent Initialization --- #
  let(:options) { { planner: mock_planner } }
  subject(:agent) { described_class.new(name: name, description: description, model_name: model_name, **options) }

  describe '#initialize' do
    it 'sets name, description, and model' do
      expect(agent.name).to eq(name)
      expect(agent.description).to eq(description)
      expect(agent.model_name).to eq(model_name)
    end

    it 'uses default model if none provided' do
      agent_default = described_class.new(name: name, description: description, planner: mock_planner)
      expect(agent_default.model_name).to eq(ADK::Agent::DEFAULT_MODEL)
    end

    it 'initializes with provided planner' do
      expect(agent.planner).to eq(mock_planner)
    end

    it 'creates default planner if not provided' do
      allow(ADK::Planner).to receive(:new).and_return(mock_planner)
      agent_default_deps = described_class.new(
        name: name,
        description: description
      )
      # Use block expectation for planner init
      expect(ADK::Planner).to have_received(:new).with(
        agent: agent_default_deps,
        model_name: ADK::Agent::DEFAULT_MODEL
      )
      expect(agent_default_deps.planner).to eq(mock_planner)
    end
  end

  # Rewrite tests for register_tool_class
  describe '#register_tool_class' do
    let(:mock_tool_class) { MockToolForAgent }
    let(:another_mock_tool_class) { AnotherMockTool }
    let(:invalid_class) { String }
    # Use a base agent without initial tools for these tests
    let(:base_agent) { described_class.new(name: name, description: description, planner: mock_planner) }

    it 'registers a valid tool class' do
      expect { base_agent.register_tool_class(mock_tool_class) }.to change {
        base_agent.tool_registry.tools.keys.count
      }.by(1)
      expect(base_agent.tool_registry.find_class(:mock_tool)).to eq(mock_tool_class)
    end

    it 'warns and overwrites when registering a duplicate tool class in agent' do
      agent = ADK::Agent.new(name: 'test_agent', description: 'Test agent')
      mock_tool_class = MockToolForAgent
      tool_name = :mock_tool

      # First registration
      agent.register_tool_class(mock_tool_class)
      expect(agent.find_tool_class(tool_name)).to eq(mock_tool_class)

      # Second registration with same tool name - expect both warning messages
      expect(ADK.logger).to receive(:warn).with("Agent 'test_agent': Tool 'mock_tool' already registered. Overwriting.").ordered
      expect(ADK.logger).to receive(:warn).with("ToolRegistry: Tool 'mock_tool' is already registered in this registry. Overwriting with class MockToolForAgent.").ordered
      agent.register_tool_class(mock_tool_class)
    end

    it 'logs error and does not register an invalid class', :log_level do
      expect(ADK.logger).to receive(:error).with(/Attempted to register invalid object/)
      expect { base_agent.register_tool_class(invalid_class) }.not_to change {
        base_agent.tool_registry.tools.keys.count
      }
    end

    it 'logs error and does not register class without metadata', :log_level do
      bad_tool_class = Class.new(ADK::Tool) # No metadata
      expect(ADK.logger).to receive(:error).with(/missing metadata/)
      expect { base_agent.register_tool_class(bad_tool_class) }.not_to change {
        base_agent.tool_registry.tools.keys.count
      }
    end

    it "registers a valid tool class" do
      agent = ADK::Agent.new(name: 'test_agent', description: 'Test agent')
      mock_tool_class = MockToolForAgent
      tool_name = :mock_tool

      agent.register_tool_class(mock_tool_class)
      expect(agent.find_tool_class(tool_name)).to eq(mock_tool_class)
    end

    it "warns and overwrites when registering a duplicate tool class in agent" do
      agent = ADK::Agent.new(name: 'test_agent', description: 'Test agent')
      mock_tool_class = MockToolForAgent
      tool_name = :mock_tool

      # First registration
      agent.register_tool_class(mock_tool_class)
      expect(agent.find_tool_class(tool_name)).to eq(mock_tool_class)

      # Second registration with same tool name - expect both warning messages
      expect(ADK.logger).to receive(:warn).with("Agent 'test_agent': Tool 'mock_tool' already registered. Overwriting.").ordered
      expect(ADK.logger).to receive(:warn).with("ToolRegistry: Tool 'mock_tool' is already registered in this registry. Overwriting with class MockToolForAgent.").ordered
      agent.register_tool_class(mock_tool_class)
    end

    it "logs error and does not register an invalid class" do
      agent = ADK::Agent.new(name: 'test_agent', description: 'Test agent')
      invalid_class = Class.new

      expect(ADK.logger).to receive(:error).with(/Attempted to register invalid object/)
      agent.register_tool_class(invalid_class)
    end

    it "logs error and does not register class without metadata" do
      agent = ADK::Agent.new(name: 'test_agent', description: 'Test agent')
      invalid_class = Class.new(ADK::Tool)

      expect(ADK.logger).to receive(:error).with("Agent 'test_agent': Tool class #{invalid_class} missing metadata (use define_metadata). Cannot register.")
      agent.register_tool_class(invalid_class)
    end

    it "warns and overwrites when registering a duplicate tool directly in registry" do
      registry = ADK::ToolRegistry.new
      mock_tool_class = MockToolForAgent
      tool_name = :mock_tool

      # First registration
      registry.register(tool_name, mock_tool_class)
      expect(registry.find_class(tool_name)).to eq(mock_tool_class)

      # Second registration with same tool name - expect only registry warning
      expect(ADK.logger).to receive(:warn).with("ToolRegistry: Tool 'mock_tool' is already registered in this registry. Overwriting with class MockToolForAgent.")
      registry.register(tool_name, mock_tool_class)
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
  end

  describe '#run_task' do
    let(:task) { "Do the thing" }
    let(:plan) { [{ tool: :mock_tool, params: { arg: 'value' } }] }
    let(:success_result_hash) { { status: :success, result: 'Done' } }
    let(:error_result_hash) { { status: :error, error_message: 'Boom' } }
    let(:session_id) { 'test-session-id' }
    let(:mock_session_service) { instance_double(ADK::SessionService::InMemory) }
    let(:mock_session) {
      instance_double(ADK::Session, id: session_id, user_id: 'test_user', app_name: name, events: [])
    }

    # Agent needs the tool class registered
    let(:agent_with_tool) {
      described_class.new(name: name, description: description, model_name: model_name, tool_classes: [MockToolForAgent],
                          **options)
    }

    # Define context mock within this describe block
    let(:mock_context) {
      instance_double(ADK::ToolContext,
                      session_id: session_id,
                      user_id: 'test_user',
                      app_name: name,
                      tool_registry: agent_with_tool.tool_registry,
                      to_h: {})
    }

    before do
      # Stub tool creation and execution
      allow(agent_with_tool.tool_registry).to receive(:create_instance).with(:mock_tool).and_return(mock_tool_instance)
      allow(mock_tool_instance).to receive(:execute).with({ arg: 'value' },
                                                          mock_context).and_return(success_result_hash)

      # Stub planner and session service
      allow(mock_planner).to receive(:plan).with(task).and_return(plan)
      allow(mock_session_service).to receive(:get_session).with(session_id: session_id).and_return(mock_session)
      allow(mock_session_service).to receive(:append_event).and_return(true)

      # Stub ToolContext.new call - Use hash_including to be less sensitive to object ID
      allow(ADK::ToolContext).to receive(:new)
        .with(hash_including(session_id: session_id,
                             user_id: 'test_user',
                             app_name: name))
        .and_return(mock_context)
    end

    it 'returns error event if agent is not running' do
      result = agent_with_tool.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
      expect(result).to be_an(ADK::Event)
      expect(result.role).to eq(:agent)
      expect(result.content).to eq({ status: :error,
                                     error_message: "Agent '#{name}' runtime is not active (stopped)." })
    end

    it 'calls planner.plan with the task' do
      agent_with_tool.start
      expect(mock_planner).to receive(:plan).with(task).and_return(plan)
      agent_with_tool.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
    end

    it 'calls execute_plan with the plan' do # Test focuses on tool execution path
      agent_with_tool.start
      expect(agent_with_tool.tool_registry).to receive(:create_instance).with(:mock_tool).and_return(mock_tool_instance)
      expect(mock_tool_instance).to receive(:execute).with({ arg: 'value' },
                                                           mock_context).and_return(success_result_hash)
      agent_with_tool.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
    end

    it 'returns the result event from execute_plan (single step)' do
      agent_with_tool.start
      result = agent_with_tool.run_task(session_id: session_id, user_input: task, session_service: mock_session_service)
      expect(result).to be_a(ADK::Event)
      expect(result.role).to eq(:agent)
      expected_content = success_result_hash.merge(
        plan_details: [{
          tool_name: :mock_tool,
          params: { arg: 'value' },
          result: success_result_hash
        }]
      )
      expect(result.content).to eq(expected_content)
    end

    context 'with multi-step plan' do
      let(:plan) { [{ tool: :mock_tool, params: { arg: 'value' } }, { tool: :another_tool, params: {} }] }
      let(:result1_hash) { { status: :success, result: 'Step 1 Done' } }
      let(:result2_hash) { { status: :success, result: 'Step 2 Done' } }
      let(:mock_tool_b_instance) { instance_double(AnotherMockTool, name: :another_tool, execute: result2_hash) }
      let(:sanitized_result1) { { status: :success, result: 'Step 1 Done' } }
      let(:sanitized_result2) { { status: :success, result: 'Step 2 Done' } }

      let(:agent_with_tools) {
        described_class.new(name: name, description: description, model_name: model_name,
                            tool_classes: [MockToolForAgent, AnotherMockTool], **options)
      }
      let(:multi_step_context) {
        instance_double(ADK::ToolContext,
                        tool_registry: agent_with_tools.tool_registry,
                        session_id: session_id,
                        user_id: 'test_user',
                        app_name: name,
                        to_h: { session_id: session_id, user_id: 'test_user', app_name: name })
      }

      before do
        agent_with_tools.start
        allow(mock_planner).to receive(:plan).with(task).and_return(plan)
        # Stub context creation for this agent
        allow(ADK::ToolContext).to receive(:new).with(hash_including(tool_registry: agent_with_tools.tool_registry)).and_return(multi_step_context)
        # Stub tool creation
        allow(agent_with_tools.tool_registry).to receive(:create_instance).with(:mock_tool).and_return(mock_tool_instance)
        allow(agent_with_tools.tool_registry).to receive(:create_instance).with(:another_tool).and_return(mock_tool_b_instance)
        # Stub execution
        allow(mock_tool_instance).to receive(:execute).with({ arg: 'value' },
                                                            multi_step_context).and_return(result1_hash)
        allow(mock_tool_b_instance).to receive(:execute).with({}, multi_step_context).and_return(result2_hash)
      end

      it 'returns the final agent event with the result of the last step' do
        result = agent_with_tools.run_task(session_id: session_id, user_input: task,
                                           session_service: mock_session_service)
        expect(result).to be_a(ADK::Event)
        expect(result.role).to eq(:agent)
        expected_content = result2_hash.merge(
          plan_details: [
            { tool_name: :mock_tool, params: { arg: 'value' }, result: sanitized_result1 },
            { tool_name: :another_tool, params: {}, result: sanitized_result2 }
          ]
        )
        expect(result.content).to eq(expected_content)
      end
    end

    context 'when planner fails' do
      before {
        agent_with_tool.start
        allow(mock_planner).to receive(:plan).and_raise(StandardError.new("Planner boom"))
      }

      it 'returns an error event' do
        result = agent_with_tool.run_task(session_id: session_id, user_input: task,
                                          session_service: mock_session_service)
        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)
        expected_error = { status: :error, error_message: "An internal error occurred: Planner boom" }
        expect(result.content).to eq(expected_error)
      end
    end

    # This context actually tests Agent behavior, not registry behavior.
    # It should ideally be in agent_spec.rb but is kept here for historical reasons or specific focus.
    context 'when execute_step fails' do
      let(:exec_error) { ADK::Error.new("Exec boom") }
      # Use a specific agent instance for this test
      let(:agent_for_exec_test) {
        ADK::Agent.new(name: 'exec_test_agent', description: 'desc', tool_classes: [MockToolForAgent],
                       planner: mock_planner)
      }
      let(:mock_tool_instance_for_exec_test) { instance_double(MockToolForAgent) }
      # This is the hash execute_step creates when rescuing the error
      let(:rescued_exec_error_hash) {
        { status: :error,
          error_message: "Internal error executing tool 'mock_tool': #{exec_error.message}",
          error_class: exec_error.class.name,
          result: nil }
      }
      # This is the final content hash expected in the agent event
      let(:expected_final_content_on_exec_error) {
        {
          status: :error,
          error_message: "Internal error executing tool 'mock_tool': #{exec_error.message}",
          error_class: exec_error.class.name,
          result: nil,
          plan_details: [{ tool_name: :mock_tool, params: { arg: "value" }, result: rescued_exec_error_hash }]
        }
      }

      before {
        agent_for_exec_test.start
        allow(mock_planner).to receive(:plan).and_return([{ tool: :mock_tool, params: { arg: 'value' } }])
        # Stub registry lookup for *this agent's* registry
        allow(agent_for_exec_test.tool_registry).to receive(:create_instance).with(:mock_tool).and_return(mock_tool_instance_for_exec_test)
        # Stub the execution on the correct instance
        allow(mock_tool_instance_for_exec_test).to receive(:execute).and_raise(exec_error)
      }

      it 'returns an error event' do
        result = agent_for_exec_test.run_task(session_id: session_id, user_input: task,
                                              session_service: mock_session_service)
        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)
        expect(result.content).to eq(expected_final_content_on_exec_error)
      end
    end
  end
end
