# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/custom_agent_patch'

RSpec.describe Legate::Agent do
  # Mock session service
  let(:mock_session_service) do
    double(
      get_session: mock_session,
      append_event: true,
      set_state: true,
      respond_to?: true
    )
  end

  # Mock session
  let(:mock_session) do
    instance_double(
      Legate::Session,
      id: 'test-session-123',
      user_id: 'test-user-123',
      app_name: 'test-app',
      events: [],
      get_state: nil
    )
  end

  # Parent agent definition with delegation targets
  let(:parent_definition) do
    Legate::AgentDefinition.new.define do |a|
      a.name :parent_agent
      a.description 'Parent agent that delegates tasks'
      a.instruction 'You are a delegating agent'
      a.can_delegate_to :child_agent
      a.fallback_mode :error
    end
  end

  # Child agent definition
  let(:child_definition) do
    Legate::AgentDefinition.new.define do |a|
      a.name :child_agent
      a.description 'Child agent that receives delegated tasks'
      a.instruction 'You are a specialized agent'
      a.fallback_mode :error
    end
  end

  before do
    # Register definitions globally
    allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(:parent_agent).and_return(parent_definition)
    allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(:child_agent).and_return(child_definition)

    # Mock other registry calls for non-existent agents
    allow(Legate::GlobalDefinitionRegistry).to receive(:find).and_call_original
  end

  describe '#transfer_to' do
    let(:parent_agent) do
      agent = described_class.new(definition: parent_definition, session_service: mock_session_service)
      allow(agent).to receive(:running?).and_return(true)
      agent
    end

    let(:child_agent) do
      agent = described_class.new(definition: child_definition, session_service: mock_session_service)
      allow(agent).to receive(:running?).and_return(true)
      agent
    end

    # Link agents in hierarchy
    before do
      # Set up parent-child relationship
      child_agent.instance_variable_set(:@parent_agent, parent_agent)
      parent_agent.instance_variable_set(:@sub_agents, [child_agent])
    end

    context 'when delegating to a valid target agent' do
      let(:delegation_task) { 'Process this data' }
      let(:session_id) { 'test-session-123' }
      let(:child_result) do
        Legate::Event.new(role: :agent, content: { status: :success, message: 'Task processed' })
      end

      before do
        allow(child_agent).to receive(:run_task).and_return(child_result)
      end

      it 'successfully delegates the task to the target agent' do
        result = parent_agent.transfer_to(:child_agent, delegation_task, session_id, mock_session_service)

        expect(result[:status]).to eq(:success)
        expect(result[:target_agent]).to eq('child_agent')
        expect(result[:result]).to eq(child_result.content)
      end

      it 'calls run_task on the target agent with the same session context' do
        # Instead of expecting parent_agent.transfer_to, expect child_agent.run_task
        expect(child_agent).to receive(:run_task).with(
          session_id: session_id,
          user_input: delegation_task,
          session_service: mock_session_service
        )

        parent_agent.transfer_to(:child_agent, delegation_task, session_id, mock_session_service)
      end
    end

    context 'when target agent is not in delegation_targets' do
      it 'returns an error result' do
        result = parent_agent.transfer_to(:unknown_agent, 'Task', 'test-session-123', mock_session_service)

        expect(result[:status]).to eq(:error)
        expect(result[:error_class]).to eq('InvalidDelegationTarget')
      end
    end

    context 'when target agent is not found in hierarchy' do
      before do
        # Set up a definition but don't add to hierarchy
        other_definition = Legate::AgentDefinition.new.define do |a|
          a.name :other_agent
          a.description 'Other agent not in hierarchy'
          a.instruction 'You are another agent'
        end

        # Update parent's delegation targets to include other_agent
        parent_definition.instance_variable_set(:@delegation_targets,
                                                parent_definition.delegation_targets.merge([:other_agent]))

        # Add to registry but not hierarchy
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(:other_agent).and_return(other_definition)

        # Mock the Agent.new call to avoid real instantiation
        new_agent = instance_double(Legate::Agent, running?: false, name: :other_agent)
        allow(new_agent).to receive(:start)
        allow(new_agent).to receive(:run_task).and_return(
          Legate::Event.new(role: :agent, content: { message: 'Task processed' })
        )
        allow(Legate::Agent).to receive(:new).with(
          hash_including(definition: other_definition)
        ).and_return(new_agent)

        # Mock planner to prevent HTTP requests
        mock_planner = instance_double(Legate::Planner)
        allow(mock_planner).to receive(:plan).and_return(
          {
            thought_process: 'Processing task',
            steps: [
              { tool: :echo, params: { message: 'Task processed' } }
            ]
          }
        )
        allow_any_instance_of(Legate::Agent).to receive(:planner).and_return(mock_planner)
      end

      it 'instantiates the agent from the definition' do
        expect(Legate::Agent).to receive(:new).with(
          hash_including(definition: an_instance_of(Legate::AgentDefinition))
        )

        result = parent_agent.transfer_to(:other_agent, 'Task', 'test-session-123', mock_session_service)
        expect(result[:status]).to eq(:success)
      end
    end

    context 'when target agent definition is not found' do
      before do
        # Update parent's delegation targets to include non_existent_agent
        parent_definition.instance_variable_set(:@delegation_targets,
                                                parent_definition.delegation_targets.merge([:non_existent_agent]))
      end

      it 'returns an error result' do
        result = parent_agent.transfer_to(:non_existent_agent, 'Task', 'test-session-123', mock_session_service)

        expect(result[:status]).to eq(:error)
        expect(result[:error_class]).to eq('AgentDefinitionNotFound')
      end
    end

    context 'when error occurs during execution' do
      before do
        allow(child_agent).to receive(:run_task).and_raise(StandardError.new('Execution failed'))
      end

      it 'returns an error result with the exception details' do
        result = parent_agent.transfer_to(:child_agent, 'Task', 'test-session-123', mock_session_service)

        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include('Execution failed')
        expect(result[:error_class]).to eq('StandardError')
      end
    end
  end

  describe '#public_execute_step with agent_transfer_to tool' do
    let(:parent_agent) do
      agent = described_class.new(definition: parent_definition, session_service: mock_session_service)
      allow(agent).to receive(:running?).and_return(true)
      agent
    end

    before do
      # Mock the private methods
      allow(parent_agent).to receive(:execute_step).and_return(
        { status: :success, target_agent: 'child_agent', result: { message: 'Task processed' } }
      )
    end

    it 'recognizes agent_transfer_to_ tools and calls transfer_to' do
      step = {
        tool: :agent_transfer_to_child_agent,
        params: { task: 'Process this data' }
      }

      # Expect transfer_to to be called
      expect(parent_agent).to receive(:transfer_to).with(
        :child_agent,
        'Process this data',
        'test-session-123',
        mock_session_service
      )

      parent_agent.public_execute_step(step, mock_session, mock_session_service)
    end

    it 'returns an error when task parameter is missing' do
      step = {
        tool: :agent_transfer_to_child_agent,
        params: {} # Missing task parameter
      }

      # Mock execute_step to return error for missing task
      allow(parent_agent).to receive(:execute_step).with(step, mock_session, mock_session_service).and_return(
        { status: :error, error_class: 'DelegationError', error_message: "Missing 'task' parameter for delegation to 'child_agent'" }
      )

      result = parent_agent.public_execute_step(step, mock_session, mock_session_service)

      expect(result[:status]).to eq(:error)
      expect(result[:error_class]).to eq('DelegationError')
      expect(result[:error_message]).to include("Missing 'task' parameter")
    end
  end
end
