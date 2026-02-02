# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/output_helper'

RSpec.describe ADK::CLI::OutputHelper do
  let(:dummy_class) do
    Class.new do
      include ADK::CLI::OutputHelper
      attr_accessor :options

      def initialize
        @options = {}
      end

      # Mock Thor's say method
      def say(message, color = nil)
        # Capture output for verification
        @last_message = message
        @last_color = color
      end

      attr_reader :last_message, :last_color
    end
  end

  subject { dummy_class.new }

  describe '#output_error' do
    context 'when providing agent metadata' do
      before do
        allow(ADK::AgentDefinitionStore).to receive(:list_all_names).and_return(['my_agent', 'other_agent'])
      end

      it 'suggests the correct agent name when a typo exists' do
        subject.output_error("Agent not found", metadata: { agent: 'my_agnt' })
        expect(subject.last_message).to include("Did you mean 'my_agent'?")
      end

      it 'does not suggest when no close match exists' do
        subject.output_error("Agent not found", metadata: { agent: 'completely_wrong' })
        expect(subject.last_message).not_to include("Did you mean")
      end
    end

    context 'when providing tool metadata' do
      before do
        allow(ADK::GlobalToolManager).to receive(:registered_tool_names).and_return([:calculator, :echo])
      end

      it 'suggests the correct tool name when a typo exists' do
        subject.output_error("Tool not found", metadata: { tool: 'calculatr' })
        expect(subject.last_message).to include("Did you mean 'calculator'?")
      end
    end

    context 'in json mode' do
      before do
        subject.options = { 'json' => true }
        allow(ADK::AgentDefinitionStore).to receive(:list_all_names).and_return(['my_agent'])
      end

      it 'includes the suggestion in the output json' do
        expect {
          subject.output_error("Agent not found", metadata: { agent: 'my_agnt' })
        }.to output(/"error_message":".*Did you mean 'my_agent'\?"/).to_stdout
      end
    end
  end
end
