# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/agent_commands'
require 'cli/ui'

RSpec.describe ADK::CLI::AgentCommands do
  let(:commands) { described_class.new }
  let(:agent_name) { 'test_agent' }
  let(:task) { 'do something' }
  let(:agent_def) { { description: 'Test Agent', tools: [], model: 'test-model' } }
  let(:agent_instance) { instance_double(ADK::Agent, start: true, stop: true, running?: false, model_name: 'test-model', tools: []) }
  let(:session_service) { ADK::SessionService::InMemory.new }

  before do
    # Mock shell to suppress output
    allow(commands).to receive(:say)

    # Mock Agent and Definition
    allow(ADK::AgentDefinitionStore).to receive(:find).with(agent_name.to_sym).and_return(agent_def)
    allow(ADK::AgentDefinition).to receive(:from_hash).and_return(instance_double(ADK::AgentDefinition, tool_names: [], name: agent_name, model_name: 'test-model'))
    allow(ADK::Agent).to receive(:new).and_return(agent_instance)

    # Mock run_task
    allow(agent_instance).to receive(:run_task).and_return({ status: :success, result: 'done' })

    # Mock Session Service injection
    # rubocop:disable Style/ClassVars
    ADK::CLI::AgentCommands.class_variable_set(:@@session_service_for_execute, session_service) if ADK::CLI::AgentCommands.class_variable_defined?(:@@session_service_for_execute)
    # rubocop:enable Style/ClassVars
  end

  describe '#execute' do
    context 'when not in quiet mode' do
      before do
        allow(commands).to receive(:options).and_return({ 'quiet' => false, 'json' => false })
        allow(::CLI::UI::StdoutRouter).to receive(:enable)
        allow(::CLI::UI::Spinner).to receive(:spin).and_yield
      end

      it 'uses CLI::UI::Spinner' do
        expect(::CLI::UI::StdoutRouter).to receive(:enable)
        expect(::CLI::UI::Spinner).to receive(:spin).with('Starting agent runtime...')
        expect(::CLI::UI::Spinner).to receive(:spin).with(/Running task in session/)

        commands.execute(agent_name, task)
      end
    end

    context 'when in quiet mode' do
      before do
        allow(commands).to receive(:options).and_return({ 'quiet' => true })
      end

      it 'does NOT use CLI::UI::Spinner' do
        expect(::CLI::UI::Spinner).not_to receive(:spin)
        commands.execute(agent_name, task)
      end
    end
  end
end
