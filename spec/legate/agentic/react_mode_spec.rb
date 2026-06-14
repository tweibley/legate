# frozen_string_literal: true

require 'spec_helper'
require 'legate/agent'
require 'legate/tool'
require 'legate/session_service/in_memory'

# End-to-end coverage of the opt-in agentic (ReAct) planning strategy: a real
# Agent + real Planner + real PlanExecutor + real Tool, with only the LLM
# adapter mocked to return scripted decisions. Proves run_task dispatches to
# the observe->think->act loop, runs tools, feeds results back, and finishes.
RSpec.describe 'Agentic ReAct planning strategy (end-to-end)', type: :integration do
  let(:session_service) { Legate::SessionService::InMemory.new }

  before do
    Legate::GlobalToolManager.reset!
    Legate::GlobalToolManager.register_tool(greeting_tool_class)
  end

  let(:greeting_tool_class) do
    Class.new(Legate::Tool) do
      self.explicit_tool_name = :greeting
      tool_description 'Returns a greeting with name'
      parameter :name, type: :string, required: true

      private

      def perform_execution(params, _context)
        { status: :success, result: "Hello, #{params[:name]}!" }
      end
    end
  end

  # A mock LLM adapter that returns scripted ReAct JSON responses in order.
  # supports_function_calling? is false so the loop exercises the deterministic
  # JSON-prompt path (the native-FC path has its own coverage in the planner spec).
  def scripted_adapter(*responses)
    adapter = instance_double(Legate::LLM::Gemini, available?: true, model_name: 'mock',
                                                   supports_function_calling?: false)
    allow(adapter).to receive(:generate).and_return(*responses)
    adapter
  end

  def build_react_agent(adapter:)
    definition = Legate::AgentDefinition.new
    definition.define do |d|
      d.name :react_agent
      d.description 'ReAct test agent'
      d.instruction 'Greet people by name.'
      d.planning_strategy :react
      d.use_tool :greeting
    end

    planner = Legate::Planner.new(agent: nil, llm_adapter: adapter)
    agent = Legate::Agent.new(
      definition: definition,
      session_service: session_service,
      planner_override: planner
    )
    # The planner needs a back-reference to the agent for tool validation.
    planner.instance_variable_set(:@agent, agent)
    agent.start
    agent
  end

  it 'runs a tool then finishes, persisting tool + final events' do
    adapter = scripted_adapter(
      '{"thought":"greet","action":"tool","tool_name":"greeting","tool_input":{"name":"World"}}',
      '{"thought":"done","action":"final","answer":"I greeted World."}'
    )
    agent = build_react_agent(adapter: adapter)
    session = session_service.create_session(app_name: 'app', user_id: 'u1')

    result = agent.run_task(session_id: session.id, user_input: 'greet World', session_service: session_service)

    expect(result.content[:status]).to eq(:success)
    expect(result.content[:result]).to eq('I greeted World.')

    events = session_service.get_session(session_id: session.id).events
    tool_results = events.select { |e| e.role == :tool_result }
    expect(tool_results.size).to eq(1)
    expect(tool_results.first.content[:result]).to eq('Hello, World!')
  end

  it 'recovers from a tool error and still reaches a final answer' do
    adapter = scripted_adapter(
      # Missing required :name -> the real Tool validation returns an error...
      '{"thought":"greet","action":"tool","tool_name":"greeting","tool_input":{}}',
      # ...which the model observes and recovers from.
      '{"thought":"retry","action":"tool","tool_name":"greeting","tool_input":{"name":"Ada"}}',
      '{"thought":"done","action":"final","answer":"Greeted Ada after a retry."}'
    )
    agent = build_react_agent(adapter: adapter)
    session = session_service.create_session(app_name: 'app', user_id: 'u1')

    result = agent.run_task(session_id: session.id, user_input: 'greet', session_service: session_service)

    expect(result.content[:status]).to eq(:success)
    expect(result.content[:result]).to eq('Greeted Ada after a retry.')

    events = session_service.get_session(session_id: session.id).events
    tool_results = events.select { |e| e.role == :tool_result }
    expect(tool_results.map { |e| e.content[:status] }).to eq(%i[error success])
  end

  it 'leaves the default (:plan) strategy untouched' do
    definition = Legate::AgentDefinition.new
    definition.define do |d|
      d.name :plain_agent
      d.description 'default'
      d.instruction 'x'
    end
    expect(definition.planning_strategy).to eq(:plan)
  end
end
