# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/output_helper'

# Helper class to include the module and mock Thor's behavior
class TestCLI
  include ADK::CLI::OutputHelper

  attr_reader :output_buffer, :options

  def initialize(options = {})
    @options = options
    @output_buffer = []
  end

  def say(message, color = nil)
    @output_buffer << { message: message, color: color }
  end

  def puts(message)
    @output_buffer << { message: message, color: nil }
  end
end

RSpec.describe ADK::CLI::OutputHelper do
  let(:cli) { TestCLI.new }
  let(:mock_store) { instance_double('ADK::DefinitionStore::RedisStore') }

  before do
    # Mock global tools
    allow(ADK::GlobalToolManager).to receive(:registered_tool_names).and_return(%i[echo calculator random_number])

    # Mock agent store
    allow(ADK).to receive_message_chain(:config, :definition_store).and_return(mock_store)
    allow(mock_store).to receive(:list_definitions).and_return([
                                                                 { name: :my_agent },
                                                                 { name: :webhook_agent },
                                                                 { name: :planner_agent }
                                                               ])
  end

  describe '#output_error' do
    context 'without metadata' do
      it 'outputs the error message in red' do
        cli.output_error('Something went wrong')
        expect(cli.output_buffer).to include(include(message: 'Something went wrong', color: :red))
      end
    end

    context 'with tool metadata' do
      it 'suggests a tool name for a typo' do
        cli.output_error('Tool not found', metadata: { tool: 'claculator' })

        expected_msg = 'Tool not found. Did you mean? calculator'
        expect(cli.output_buffer).to include(include(message: expected_msg, color: :red))
      end

      it 'does not suggest if no close match found' do
        cli.output_error('Tool not found', metadata: { tool: 'completely_wrong' })

        expect(cli.output_buffer.last[:message]).to eq('Tool not found')
      end
    end

    context 'with agent metadata' do
      it 'suggests an agent name for a typo' do
        cli.output_error('Agent not found', metadata: { agent: 'my_agnt' })

        expected_msg = 'Agent not found. Did you mean? my_agent'
        expect(cli.output_buffer).to include(include(message: expected_msg, color: :red))
      end
    end

    context 'in JSON mode' do
      let(:cli) { TestCLI.new(json: true) }

      it 'includes suggestion in JSON output' do
        cli.output_error('Tool not found', metadata: { tool: 'echoo' })

        json_output = JSON.parse(cli.output_buffer.last[:message])
        expect(json_output['status']).to eq('error')
        expect(json_output['suggestion']).to eq('echo')
      end
    end
  end
end
