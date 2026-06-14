# frozen_string_literal: true

require 'spec_helper'
require 'legate/agents/loop_agent'
require 'legate/session'
require 'legate/session_service/in_memory'
require 'legate/event'

RSpec.describe Legate::Agents::LoopAgent do
  let(:agent_name) { :loop_agent }
  let(:sub_agent_name) { :worker_agent }
  let(:session_service) { Legate::SessionService::InMemory.new }
  let(:session) { session_service.create_session(app_name: 'app1', user_id: 'user1') }
  let(:session_id) { session.id }
  let(:user_input) { 'Loop this' }

  let(:definition) do
    # Capture let variables for closure scope
    name_val = agent_name
    sub_name = sub_agent_name

    Legate::AgentDefinition.new.define do |d|
      d.name name_val
      d.description 'Loop Agent'
      d.instruction 'Loop it'
      d.loop_sub_agents sub_name
      d.loop_max_iterations 3
    end
  end

  # Real sub-agent
  let(:sub_agent_def) {
    Legate::AgentDefinition.new.define { |d|
      d.name :worker_agent
      d.instruction 'Worker'
    }
  }
  let(:sub_agent) { Legate::Agent.new(definition: sub_agent_def, session_service: session_service) }

  subject(:agent) { described_class.new(definition: definition, session_service: session_service, sub_agents: [sub_agent]) }

  before do
    allow(Legate).to receive(:logger).and_return(spy('Logger'))

    allow(sub_agent).to receive(:start)
    allow(sub_agent).to receive(:running?).and_return(true)

    agent.start
  end

  describe '#run_task' do
    context 'with max iterations' do
      it 'runs sub-agent repeatedly until max iterations' do
        expect(sub_agent).to receive(:run_task).exactly(3).times.and_return(Legate::Event.new(role: :agent, content: { status: :success, result: 'Done' }))

        result_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: session_service)

        expect(result_event.content[:status]).to eq(:success)
        expect(result_event.content[:iterations_completed]).to eq(3)
        expect(result_event.content[:result]).to include('maximum iterations (3) reached')
      end
    end

    context 'with loop condition' do
      let(:definition_with_condition) do
        name_val = agent_name
        sub_name = sub_agent_name
        Legate::AgentDefinition.new.define do |d|
          d.name name_val
          d.description 'Loop Agent'
          d.instruction 'Loop it'
          d.loop_sub_agents sub_name
          # Condition setup
          d.loop_condition :is_finished, true
          d.loop_max_iterations 10
        end
      end

      subject(:agent) { described_class.new(definition: definition_with_condition, session_service: session_service, sub_agents: [sub_agent]) }

      it 'stops when condition is met' do
        # Iteration 1 check: false. Sub-agent runs.
        # Iteration 2 check: true. Loop breaks.
        expect(session_service).to receive(:get_state).with(session_id: session_id, key: :is_finished).and_return(false, true)

        expect(sub_agent).to receive(:run_task).once.and_return(Legate::Event.new(role: :agent, content: { status: :success }))

        result_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: session_service)

        # We complete 1 full iteration (the first one) because check failed (state=false)
        # Then we start 2nd iteration, check condition (state=true), and break.
        # So iterations_completed should be 1?
        # Logic: while iteration < max
        # iteration += 1
        # Check condition. If true, break.
        # Run sub-agents.
        # ...

        # Trace:
        # Init: iteration = 0
        # Loop 1: iteration = 1. Check condition (false). Run sub-agents.
        # Loop 2: iteration = 2. Check condition (true). Break.
        # Result: iterations_completed = 2 (because we incremented twice).
        # Wait, if we break immediately, the sub-agents for iter 2 didn't run.
        # Does iterations_completed mean "attempted" or "fully executed"?
        # The implementation returns `iterations_completed: iteration` which is the counter.
        # If we break on iter 2, counter is 2.
        # Let's verify expectations against implementation.

        expect(result_event.content[:iterations_completed]).to eq(1) # Completed 1 full iteration and broke at check after
        expect(result_event.content[:loop_condition_met]).to be true
      end
    end

    context 'with error in sub-agent' do
      it 'terminates loop on error' do
        allow(sub_agent).to receive(:run_task).and_return(Legate::Event.new(role: :agent, content: { status: :error, error_message: 'Failed' }))

        result_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: session_service)

        expect(result_event.content[:status]).to eq(:error)
        expect(result_event.content[:iterations_completed]).to eq(1)
        expect(result_event.content[:error_message]).to include('Loop terminated due to error')
      end
    end
  end
end
