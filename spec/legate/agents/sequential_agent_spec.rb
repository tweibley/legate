# frozen_string_literal: true

require 'spec_helper'
require 'legate/agents/sequential_agent'
require 'legate/session'
require 'legate/session_service/in_memory'
require 'legate/event'

RSpec.describe Legate::Agents::SequentialAgent do
  let(:agent_name) { :sequential_agent }
  let(:sub_agent_1_name) { :sub_agent_1 }
  let(:sub_agent_2_name) { :sub_agent_2 }
  let(:session_service) { Legate::SessionService::InMemory.new }
  let(:session) { session_service.create_session(app_name: 'app1', user_id: 'user1') }
  let(:session_id) { session.id }
  let(:user_input) { 'Start sequence' }

  # Definitions
  let(:sub_agent_1_def) {
    Legate::AgentDefinition.new.define { |d|
      d.name :sub_agent_1
      d.instruction 'I am 1'
      d.output_key :result_1
    }
  }
  let(:sub_agent_2_def) {
    Legate::AgentDefinition.new.define { |d|
      d.name :sub_agent_2
      d.instruction 'I am 2'
      d.output_key :result_2
    }
  }

  let(:definition) do
    # Capture let variables for closure scope
    name_val = agent_name
    sub_1 = sub_agent_1_name
    sub_2 = sub_agent_2_name

    Legate::AgentDefinition.new.define do |d|
      d.name name_val
      d.description 'Sequential Agent'
      d.instruction 'Run in sequence'
      d.sequential_sub_agents sub_1, sub_2
    end
  end

  # Real sub-agents
  let(:sub_agent_1) { Legate::Agent.new(definition: sub_agent_1_def, session_service: session_service) }
  let(:sub_agent_2) { Legate::Agent.new(definition: sub_agent_2_def, session_service: session_service) }

  subject(:agent) { described_class.new(definition: definition, session_service: session_service, sub_agents: [sub_agent_1, sub_agent_2]) }

  before do
    allow(Legate).to receive(:logger).and_return(spy('Logger'))

    # Stub start/run_task to avoid actual execution logic but keep object identity
    allow(sub_agent_1).to receive(:start)
    allow(sub_agent_2).to receive(:start)
    allow(sub_agent_1).to receive(:running?).and_return(true)
    allow(sub_agent_2).to receive(:running?).and_return(true)

    agent.start
  end

  describe '#run_task' do
    it 'executes sub-agents in order' do
      expect(sub_agent_1).to receive(:run_task).ordered.and_return(Legate::Event.new(role: :agent, content: { status: :success, result: 'Result 1' }))
      expect(sub_agent_2).to receive(:run_task).ordered.and_return(Legate::Event.new(role: :agent, content: { status: :success, result: 'Result 2' }))

      result_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: session_service)

      expect(result_event.content[:status]).to eq(:success)
      expect(result_event.content[:steps_completed]).to eq(2)
      expect(result_event.content[:sub_results].first[:result][:result]).to eq('Result 1')
    end

    it 'passes previous result to next agent input' do
      allow(sub_agent_1).to receive(:run_task).and_return(Legate::Event.new(role: :agent, content: { status: :success, result: 'Result 1' }))

      # Manually set state since we mocked run_task which would normally do it
      session_service.set_state(session_id: session_id, key: :result_1, value: { result: 'Result 1' })

      expect(sub_agent_2).to receive(:run_task) do |args|
        expect(args[:user_input]).to include('Result 1')
        Legate::Event.new(role: :agent, content: { status: :success, result: 'Result 2' })
      end

      agent.run_task(session_id: session_id, user_input: user_input, session_service: session_service)
    end

    it 'stops execution if a sub-agent fails' do
      allow(sub_agent_1).to receive(:run_task).and_return(Legate::Event.new(role: :agent, content: { status: :error, error_message: 'Boom' }))

      expect(sub_agent_2).not_to receive(:run_task)

      result_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: session_service)

      expect(result_event.content[:status]).to eq(:error)
      expect(result_event.content[:error_message]).to include('Boom')
      expect(result_event.content[:step]).to eq(1)
    end
  end
end
