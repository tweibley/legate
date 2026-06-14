# frozen_string_literal: true

require 'spec_helper'
require 'legate/agent'
require 'legate/tool'
require 'legate/session_service/in_memory'

# Coverage for the one-shot Agent#ask convenience runner (DX1): real Agent +
# real Tool + InMemory, planner stubbed to a one-step plan.
RSpec.describe 'Agent#ask', type: :integration do
  let(:session_service) { Legate::SessionService::InMemory.new }

  before do
    Legate::GlobalToolManager.reset!
    Legate::GlobalToolManager.register_tool(greeting_tool_class)
  end

  let(:greeting_tool_class) do
    Class.new(Legate::Tool) do
      self.explicit_tool_name = :greeting
      tool_description 'Greets a name'
      parameter :name, type: :string, required: true
      def perform_execution(params, _ctx) = { status: :success, result: "Hello, #{params[:name]}!" }
    end
  end

  let(:planner) do
    instance_double(Legate::Planner).tap do |p|
      allow(p).to receive(:plan).and_return(
        { steps: [{ tool: :greeting, params: { name: 'World' }, reason: 'greet' }] }
      )
    end
  end

  def build_agent
    definition = Legate::AgentDefinition.new
    definition.define do |d|
      d.name :greeter
      d.description 'Greets'
      d.instruction 'Greet people.'
      d.use_tool :greeting
    end
    Legate::Agent.new(definition: definition, session_service: session_service, planner_override: planner)
  end

  it 'lazy-starts the agent, creates a session, and returns the answer in one call' do
    agent = build_agent
    expect(agent.running?).to be false

    event = agent.ask('greet World')

    expect(agent.running?).to be true # auto-started
    expect(event.success?).to be true
    expect(event.answer).to eq('Hello, World!')
  end

  it 'reuses a passed session_id to continue a conversation' do
    agent = build_agent
    agent.start
    session = session_service.create_session(app_name: 'greeter', user_id: 'u1')

    agent.ask('first', session_id: session.id)
    agent.ask('second', session_id: session.id)

    events = session_service.get_session(session_id: session.id).events
    # Two full turns recorded in the same session (each: user + tool_request + tool_result + agent).
    expect(events.count { |e| e.role == :user }).to eq(2)
  end

  it 'forwards a block to run_task as the on_event stream' do
    agent = build_agent
    streamed = []
    agent.ask('greet World') { |event| streamed << event.role }
    expect(streamed).to eq(%i[user tool_request tool_result agent])
  end

  it 'creates a distinct session per call when no session_id is given' do
    agent = build_agent
    agent.ask('one')
    agent.ask('two')
    expect(session_service.list_sessions(app_name: 'greeter').size).to eq(2)
  end
end
