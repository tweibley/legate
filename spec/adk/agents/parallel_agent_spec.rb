# frozen_string_literal: true

require 'spec_helper'
require 'adk/agents/parallel_agent'
require 'adk/session'
require 'adk/session_service/in_memory'
require 'adk/event'
require 'concurrent'

RSpec.describe ADK::Agents::ParallelAgent do
  let(:agent_name) { :parallel_agent }
  let(:sub_agent_1_name) { :sub_agent_1 }
  let(:sub_agent_2_name) { :sub_agent_2 }
  let(:session_service) { ADK::SessionService::InMemory.new }
  let(:session) { session_service.create_session(app_name: 'app1', user_id: 'user1') }
  let(:session_id) { session.id }
  let(:user_input) { 'Run in parallel' }

  let(:definition) do
    # Capture let variables for closure scope
    name_val = agent_name
    sub_1 = sub_agent_1_name
    sub_2 = sub_agent_2_name

    ADK::AgentDefinition.new.define do |d|
      d.name name_val
      d.description 'Parallel Agent'
      d.instruction 'Run parallel'
      d.parallel_sub_agents sub_1, sub_2
    end
  end

  # Definitions & Real Sub-Agents
  let(:sub_agent_1_def) { ADK::AgentDefinition.new.define { |d| d.name :sub_agent_1; d.instruction 'I am 1' } }
  let(:sub_agent_2_def) { ADK::AgentDefinition.new.define { |d| d.name :sub_agent_2; d.instruction 'I am 2' } }

  let(:sub_agent_1) { ADK::Agent.new(definition: sub_agent_1_def, session_service: session_service) }
  let(:sub_agent_2) { ADK::Agent.new(definition: sub_agent_2_def, session_service: session_service) }

  subject(:agent) { described_class.new(definition: definition, session_service: session_service, sub_agents: [sub_agent_1, sub_agent_2]) }

  before do
    allow(ADK).to receive(:logger).and_return(spy('Logger'))
    
    allow(sub_agent_1).to receive(:start)
    allow(sub_agent_2).to receive(:start)
    allow(sub_agent_1).to receive(:running?).and_return(true)
    allow(sub_agent_2).to receive(:running?).and_return(true)
    
    agent.start
  end

  describe '#run_task' do
    it 'executes sub-agents concurrently' do
      expect(sub_agent_1).to receive(:run_task).and_return(ADK::Event.new(role: :agent, content: { status: :success, result: 'Result 1' }))
      expect(sub_agent_2).to receive(:run_task).and_return(ADK::Event.new(role: :agent, content: { status: :success, result: 'Result 2' }))

      result_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: session_service)
      
      expect(result_event.content[:status]).to eq(:success)
      expect(result_event.content[:sub_results][sub_agent_1_name][:result]).to eq('Result 1')
      expect(result_event.content[:sub_results][sub_agent_2_name][:result]).to eq('Result 2')
    end

    it 'handles errors in one sub-agent gracefully' do
      allow(sub_agent_1).to receive(:run_task).and_return(ADK::Event.new(role: :agent, content: { status: :success, result: 'Result 1' }))
      allow(sub_agent_2).to receive(:run_task).and_raise(StandardError, 'Fail')

      result_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: session_service)
      
      expect(result_event.content[:status]).to eq(:partial_success)
      expect(result_event.content[:sub_results][sub_agent_1_name][:status]).to eq(:success)
      expect(result_event.content[:sub_results][sub_agent_2_name][:status]).to eq(:error)
      expect(result_event.content[:sub_results][sub_agent_2_name][:error_message]).to include('Fail')
    end

    it 'handles agent returning error status' do
        allow(sub_agent_1).to receive(:run_task).and_return(ADK::Event.new(role: :agent, content: { status: :success, result: 'Result 1' }))
        allow(sub_agent_2).to receive(:run_task).and_return(ADK::Event.new(role: :agent, content: { status: :error, error_message: 'Logic Error' }))
  
        result_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: session_service)
        
        expect(result_event.content[:status]).to eq(:partial_success)
        expect(result_event.content[:sub_results][sub_agent_2_name][:error_message]).to include('Logic Error')
    end
  end
end
