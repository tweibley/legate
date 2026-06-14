# frozen_string_literal: true

require 'spec_helper'
require 'legate/agent'
require 'legate/tool'
require 'legate/session_service/in_memory'

# Regression: a planning failure on a single-tool agent (no echo) must return a
# clean error Event with a real message — not an empty answer / a hard
# "Echo tool not available" failure (DX4 Part A).
RSpec.describe 'Agent planning failure (no echo dependency)', type: :integration do
  let(:session_service) { Legate::SessionService::InMemory.new }

  before do
    Legate::GlobalToolManager.reset!
    Legate::GlobalToolManager.register_tool(calc_tool_class)
  end

  let(:calc_tool_class) do
    Class.new(Legate::Tool) do
      self.explicit_tool_name = :only_tool
      tool_description 'the only tool (no echo registered)'
      def perform_execution(_params, _ctx) = { status: :success, result: 'ok' }
    end
  end

  def build_agent(planner)
    definition = Legate::AgentDefinition.new
    definition.define do |d|
      d.name :lonely_agent
      d.description 'has one tool, no echo'
      d.use_tool :only_tool
    end
    agent = Legate::Agent.new(definition: definition, session_service: session_service, planner_override: planner)
    agent.start
    agent
  end

  it 'returns a clean error event when the planner reports a direct failure' do
    planner = instance_double(Legate::Planner)
    allow(planner).to receive(:plan).and_return(
      { thought_process: 'Planning failed', direct_result: { status: :error, error_message: 'the model fell over' } }
    )
    agent = build_agent(planner)
    session = session_service.create_session(app_name: 'app', user_id: 'u1')

    event = agent.run_task(session_id: session.id, user_input: 'do a thing', session_service: session_service)

    expect(event.error?).to be true
    expect(event.success?).to be false
    expect(event.error_message).to eq('the model fell over')
    expect(event.answer).to be_nil
  end

  it 'returns a clean error event for an empty plan (no echo to fall back to)' do
    planner = instance_double(Legate::Planner)
    allow(planner).to receive(:plan).and_return({ thought_process: 'nothing to do', steps: [] })
    agent = build_agent(planner)
    session = session_service.create_session(app_name: 'app', user_id: 'u1')

    event = agent.run_task(session_id: session.id, user_input: 'do a thing', session_service: session_service)

    expect(event.error?).to be true
    expect(event.error_message).to be_a(String)
    expect(event.error_message).not_to be_empty
  end
end
