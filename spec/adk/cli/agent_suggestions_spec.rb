# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/agent_commands'
require 'adk/agent_definition_store'
require 'stringio'
require 'thor/shell/basic'

RSpec.describe ADK::CLI::AgentCommands do
  let(:commands) { described_class.new }
  let(:output) { StringIO.new }
  let(:shell) { Thor::Shell::Basic.new }

  before do
    allow(shell).to receive(:stdout).and_return(output)
    allow(shell).to receive(:stderr).and_return(output)
    commands.shell = shell

    # Stub exit to raise SystemExit so we verify flow stops
    allow(commands).to receive(:exit).with(1).and_raise(SystemExit)
  end

  describe '#handle_agent_not_found (helper behavior via commands)' do
    before do
      allow(ADK::AgentDefinitionStore).to receive(:all_names).and_return(['my_awesome_agent', 'test_agent'])
    end

    context 'when executing a command with a typo in agent name' do
      before do
        allow(ADK::AgentDefinitionStore).to receive(:find).with(:my_awesom_agent).and_return(nil)
        allow(ADK::AgentDefinitionStore).to receive(:load_from_redis).with(:my_awesom_agent).and_return(nil)
      end

      it 'suggests the correct agent name' do
        expect {
          commands.execute('my_awesom_agent', 'hello')
        }.to raise_error(SystemExit)

        expect(output.string).to include("Agent definition 'my_awesom_agent' not found.")
        expect(output.string).to include("Did you mean 'my_awesome_agent'?")
      end
    end

    context 'when executing a command with a completely wrong name' do
      before do
        allow(ADK::AgentDefinitionStore).to receive(:find).with(:completely_wrong).and_return(nil)
        allow(ADK::AgentDefinitionStore).to receive(:load_from_redis).with(:completely_wrong).and_return(nil)
      end

      it 'does not offer suggestions' do
        expect {
          commands.execute('completely_wrong', 'hello')
        }.to raise_error(SystemExit)

        expect(output.string).to include("Agent definition 'completely_wrong' not found.")
        expect(output.string).not_to include("Did you mean")
      end
    end
  end
end
