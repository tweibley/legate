# frozen_string_literal: true

require 'spec_helper'
require 'legate/agent'
require 'legate/tool'
require 'legate/session_service/in_memory'

# End-to-end coverage of run_task's on_event streaming (R3): a real Agent +
# real Tool + InMemory service, with only the planner stubbed to produce a
# one-step plan. Asserts lifecycle events are delivered live and in order, the
# return value is unchanged, and the subscription is torn down.
RSpec.describe 'Agent#run_task event streaming', type: :integration do
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

      private

      def perform_execution(params, _context)
        { status: :success, result: "Hello, #{params[:name]}!" }
      end
    end
  end

  # Planner that returns a fixed one-step plan (calls :greeting), no LLM.
  let(:planner) do
    instance_double(Legate::Planner).tap do |p|
      allow(p).to receive(:plan).and_return(
        { thought_process: 'greet', steps: [{ tool: :greeting, params: { name: 'World' }, reason: 'greet' }] }
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
    agent = Legate::Agent.new(definition: definition, session_service: session_service, planner_override: planner)
    agent.start
    agent
  end

  it 'streams lifecycle events live and in order' do
    agent = build_agent
    session = session_service.create_session(app_name: 'app', user_id: 'u1')

    streamed = []
    final = agent.run_task(session_id: session.id, user_input: 'greet World',
                           session_service: session_service, on_event: ->(e) { streamed << e })

    expect(streamed.map(&:role)).to eq(%i[user tool_request tool_result agent])
    # The tool result event carries the real tool output.
    expect(streamed[2].content[:result]).to eq('Hello, World!')
    # The streamed final event is the same object returned to the caller.
    expect(streamed.last).to eq(final)
    expect(final.content[:result]).to eq('Hello, World!')
  end

  it 'returns the identical result whether or not on_event is supplied' do
    session = session_service.create_session(app_name: 'app', user_id: 'u1')
    without = build_agent.run_task(session_id: session.id, user_input: 'greet World', session_service: session_service)

    session2 = session_service.create_session(app_name: 'app', user_id: 'u1')
    with = build_agent.run_task(session_id: session2.id, user_input: 'greet World',
                                session_service: session_service, on_event: ->(_e) {})

    expect(with.content).to eq(without.content)
  end

  it 'tears down the subscription after the run (no leak)' do
    agent = build_agent
    session = session_service.create_session(app_name: 'app', user_id: 'u1')

    streamed = []
    agent.run_task(session_id: session.id, user_input: 'greet World',
                   session_service: session_service, on_event: ->(e) { streamed << e })
    count_after_run = streamed.size

    # A later append to the same session must not reach the old callback.
    session_service.append_event(session_id: session.id, event: Legate::Event.new(role: :agent, content: { status: :success }))
    expect(streamed.size).to eq(count_after_run)
  end
end
