# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/agent_commands'
require 'adk/agent_definition_store'
require 'thor/shell/basic'

RSpec.describe ADK::CLI::AgentCommands do
  let(:commands) { described_class.new }
  let(:output) { StringIO.new }
  let(:shell) { Thor::Shell::Basic.new }

  before do
    allow(shell).to receive(:stdout).and_return(output)
    allow(shell).to receive(:stderr).and_return(output)
    commands.shell = shell

    # Mock exit to prevent actual exit
    allow(commands).to receive(:exit)

    # Mock AgentDefinitionStore.list_all_names default
    allow(ADK::AgentDefinitionStore).to receive(:list_all_names).and_return([])
  end

  # Helper to invoke command
  def invoke_command(command_name, *args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    commands.options = options
    commands.invoke(command_name, args, options)
  rescue SystemExit
    # Capture exit
  end

  describe 'Did You Mean suggestions' do
    context 'when similar agent exists' do
      before do
        allow(ADK::AgentDefinitionStore).to receive(:list_all_names).and_return(['my_agent', 'other_agent'])
      end

      it 'suggests the similar name for status command' do
        # Mock load_from_redis to return nil (not found)
        allow(ADK::AgentDefinitionStore).to receive(:load_from_redis).with(:my_agnte).and_return(nil)

        invoke_command(:status, 'my_agnte')

        expect(output.string).to include("Agent definition 'my_agnte' not found.")
        expect(output.string).to include("Did you mean 'my_agent'?")
      end

       it 'suggests the similar name for start command' do
        allow(ADK::GlobalDefinitionRegistry).to receive(:find).and_return(nil)
        allow(ADK::AgentDefinitionStore).to receive(:load_from_redis).with(:my_agnte).and_return(nil)

        invoke_command(:start, 'my_agnte')

        expect(output.string).to include("Agent definition 'my_agnte' not found.")
        expect(output.string).to include("Did you mean 'my_agent'?")
      end

      it 'suggests the similar name for delete command' do
        allow(ADK::AgentDefinitionStore).to receive(:find).with(:my_agnte).and_return(nil)
        allow(ADK::AgentDefinitionStore).to receive(:load_from_redis).with(:my_agnte).and_return(nil)

        invoke_command(:delete, 'my_agnte')

        expect(output.string).to include("Error: Agent definition 'my_agnte' not found.")
        expect(output.string).to include("Did you mean 'my_agent'?")
      end
    end

    context 'when no similar agent exists' do
      before do
        allow(ADK::AgentDefinitionStore).to receive(:list_all_names).and_return(['completely_different'])
      end

      it 'does not offer suggestion' do
        allow(ADK::AgentDefinitionStore).to receive(:load_from_redis).with(:my_agnte).and_return(nil)

        invoke_command(:status, 'my_agnte')

        expect(output.string).to include("Agent definition 'my_agnte' not found.")
        expect(output.string).not_to include("Did you mean")
      end
    end

    context 'when Redis fails to list names' do
      before do
        # simulate list_all_names failing or returning empty
         allow(ADK::AgentDefinitionStore).to receive(:list_all_names).and_return([])
      end

      it 'does not crash and shows standard error' do
        allow(ADK::AgentDefinitionStore).to receive(:load_from_redis).with(:my_agnte).and_return(nil)

        invoke_command(:status, 'my_agnte')

        expect(output.string).to include("Agent definition 'my_agnte' not found.")
      end
    end
  end
end
