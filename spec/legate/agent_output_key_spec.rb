# frozen_string_literal: true

require 'spec_helper'
require 'legate/agent'
require 'legate/session_service/in_memory'

# Regression coverage: storing an agent's result under an output_key must not
# assume the result is a Hash. A tool (or callback) returning a bare scalar/array
# previously crashed _store_output_in_session with NoMethodError (#key? on a
# non-Hash), turning a successful run into an error.
RSpec.describe 'Agent#run_task output_key with non-Hash results', type: :integration do
  let(:session_service) { Legate::SessionService::InMemory.new }

  before do
    Legate::GlobalToolManager.reset!
    Legate::GlobalToolManager.register_tool(scalar_tool_class)
  end

  let(:scalar_tool_class) do
    Class.new(Legate::Tool) do
      self.explicit_tool_name = :scalar
      tool_description 'Returns a bare string result'
      def perform_execution(_params, _ctx) = { status: :success, result: 'a bare string' }
    end
  end

  def build_agent
    planner = instance_double(Legate::Planner)
    allow(planner).to receive(:plan).and_return({ steps: [{ tool: :scalar, params: {}, reason: 'x' }] })
    definition = Legate::AgentDefinition.new
    definition.define do |d|
      d.name :scalar_agent
      d.description 'd'
      d.instruction 'i'
      d.use_tool :scalar
      d.output_key :saved
    end
    agent = Legate::Agent.new(definition: definition, session_service: session_service, planner_override: planner)
    agent.start
    agent
  end

  it 'stores a non-Hash final result under the output_key without crashing' do
    agent = build_agent
    session = session_service.create_session(app_name: 'app', user_id: 'u1')

    event = nil
    expect do
      event = agent.run_task(session_id: session.id, user_input: 'go', session_service: session_service)
    end.not_to raise_error

    expect(event.content[:status]).to eq(:success)
    # The output_key state was written (value is the result, however serialized).
    expect(session_service.get_state(session_id: session.id, key: :saved)).not_to be_nil
  end

  it 'directly: _store_output_in_session tolerates a scalar event content' do
    agent = build_agent
    session = session_service.create_session(app_name: 'app', user_id: 'u1')
    scalar_event = Legate::Event.new(role: :agent, content: 'just a string')

    expect do
      agent.send(:_store_output_in_session, scalar_event, session.id, session_service)
    end.not_to raise_error
    expect(session_service.get_state(session_id: session.id, key: :saved)).to eq('just a string')
  end
end
