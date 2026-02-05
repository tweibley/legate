# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/output_helper'
require 'adk/agent_definition_store'
require 'adk/global_tool_manager'
require 'thor'

# Test class to mix in the helper
class TestCLI < Thor
  include ADK::CLI::OutputHelper
end

RSpec.describe ADK::CLI::OutputHelper do
  let(:cli) { TestCLI.new }
  let(:shell) { Thor::Shell::Basic.new }
  let(:output) { StringIO.new }

  before do
    allow(shell).to receive(:stdout).and_return(output)
    allow(shell).to receive(:stderr).and_return(output)
    cli.shell = shell
  end

  describe '#output_error' do
    context 'with agent metadata' do
      before do
        allow(ADK::AgentDefinitionStore).to receive(:list_all_names).and_return(['my_agent', 'other_agent'])
      end

      it 'suggests corrections for agent names' do
        cli.output_error('Agent not found', metadata: { agent: 'my_agnt' })
        expect(output.string).to include("Did you mean 'my_agent'?")
      end

      it 'does not suggest if no match found' do
        cli.output_error('Agent not found', metadata: { agent: 'totally_wrong' })
        expect(output.string).not_to include("Did you mean")
      end
    end

    context 'with tool metadata' do
      before do
        allow(ADK::GlobalToolManager).to receive(:registered_tool_names).and_return([:echo_tool, :calc_tool])
      end

      it 'suggests corrections for tool names' do
        cli.output_error('Tool not found', metadata: { tool: 'echo_tol' })
        expect(output.string).to include("Did you mean 'echo_tool'?")
      end
    end

    context 'without metadata' do
      it 'outputs the error message normally' do
        cli.output_error('Some error')
        expect(output.string).to include('Some error')
        expect(output.string).not_to include("Did you mean")
      end
    end

    context 'when Redis fails for agents' do
      before do
        allow(ADK::AgentDefinitionStore).to receive(:list_all_names).and_return([])
      end

      it 'does not crash and does not suggest' do
        cli.output_error('Agent not found', metadata: { agent: 'my_agnt' })
        expect(output.string).to include('Agent not found')
        expect(output.string).not_to include("Did you mean")
      end
    end
  end
end
