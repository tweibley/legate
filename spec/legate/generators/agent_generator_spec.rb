# frozen_string_literal: true

require 'spec_helper'
require 'legate/generators/agent_generator'

RSpec.describe Legate::Generators::AgentGenerator do
  let(:adapter) { instance_double(Legate::LLM::Gemini, available?: true) }

  before do
    allow(Legate::LLM).to receive(:build_adapter).and_return(adapter)
    # Deterministic set of "installed" tools for tool-filtering assertions.
    allow(Legate::GlobalToolManager).to receive(:list_all_tools).and_return(
      [
        { name: :echo, description: 'Echo', parameters: {} },
        { name: :calculator, description: 'Math', parameters: {} }
      ]
    )
  end

  def definition_json(overrides = {})
    {
      'name' => 'My Helper Agent',
      'description' => 'Helps with stuff',
      'instruction' => 'Be helpful.',
      'model' => 'gemini-3.5-flash',
      'agent_type' => 'llm',
      'tools' => %w[echo calculator],
      'output_key' => ''
    }.merge(overrides).to_json
  end

  describe '.generate_definition' do
    it 'returns structured fields parsed from the LLM JSON' do
      allow(adapter).to receive(:generate).and_return(definition_json)
      result = described_class.generate_definition(description: 'a helper')

      expect(result[:description]).to eq('Helps with stuff')
      expect(result[:instruction]).to eq('Be helpful.')
      expect(result[:model]).to eq('gemini-3.5-flash')
      expect(result[:agent_type]).to eq('llm')
      expect(result[:tools]).to contain_exactly('echo', 'calculator')
      expect(result[:dropped_tools]).to be_empty
    end

    it 'sanitizes the name to a snake_case identifier' do
      allow(adapter).to receive(:generate).and_return(definition_json('name' => 'My Helper Agent'))
      expect(described_class.generate_definition(description: 'x')[:name]).to eq('my_helper_agent')
    end

    it 'drops hallucinated tools that are not installed' do
      allow(adapter).to receive(:generate).and_return(definition_json('tools' => %w[echo send_email weather]))
      result = described_class.generate_definition(description: 'x')
      expect(result[:tools]).to eq(['echo'])
      expect(result[:dropped_tools]).to contain_exactly('send_email', 'weather')
    end

    it 'surfaces model-proposed missing tools as suggested_tools (sanitized)' do
      allow(adapter).to receive(:generate).and_return(definition_json(
                                                        'tools' => ['echo'],
                                                        'suggested_tools' => [{ 'name' => 'Send Email', 'description' => 'Sends an email' }]
                                                      ))
      result = described_class.generate_definition(description: 'x')
      expect(result[:tools]).to eq(['echo'])
      expect(result[:suggested_tools]).to contain_exactly(
        a_hash_including(name: 'send_email', description: 'Sends an email')
      )
    end

    it 'folds hallucinated tools from the tools array into suggested_tools' do
      allow(adapter).to receive(:generate).and_return(definition_json('tools' => %w[echo weather_lookup], 'suggested_tools' => []))
      result = described_class.generate_definition(description: 'x')
      expect(result[:suggested_tools].map { |t| t[:name] }).to include('weather_lookup')
    end

    it 'never suggests a tool that is already installed' do
      allow(adapter).to receive(:generate).and_return(definition_json('suggested_tools' => [{ 'name' => 'echo', 'description' => 'dup' }]))
      expect(described_class.generate_definition(description: 'x')[:suggested_tools]).to be_empty
    end

    it 'defaults an unknown agent_type to llm' do
      allow(adapter).to receive(:generate).and_return(definition_json('agent_type' => 'wizard'))
      expect(described_class.generate_definition(description: 'x')[:agent_type]).to eq('llm')
    end

    it 'defaults a blank model to the agent default model' do
      allow(adapter).to receive(:generate).and_return(definition_json('model' => ''))
      expect(described_class.generate_definition(description: 'x')[:model]).to eq(Legate::Agent::DEFAULT_MODEL)
    end

    it 'falls back to the description input when the model omits one' do
      allow(adapter).to receive(:generate).and_return(definition_json('description' => ''))
      expect(described_class.generate_definition(description: 'fallback desc')[:description]).to eq('fallback desc')
    end

    it 'strips markdown fences around the JSON' do
      allow(adapter).to receive(:generate).and_return("```json\n#{definition_json}\n```")
      expect(described_class.generate_definition(description: 'x')[:name]).to eq('my_helper_agent')
    end

    it 'raises GenerationError on invalid JSON' do
      allow(adapter).to receive(:generate).and_return('not json at all')
      expect { described_class.generate_definition(description: 'x') }
        .to raise_error(described_class::GenerationError, /JSON/)
    end

    it 'raises GenerationError when the name is missing' do
      allow(adapter).to receive(:generate).and_return(definition_json('name' => ''))
      expect { described_class.generate_definition(description: 'x') }
        .to raise_error(described_class::GenerationError, /name/)
    end

    it 'raises ApiKeyMissingError when the adapter is unavailable' do
      allow(adapter).to receive(:available?).and_return(false)
      expect { described_class.generate_definition(description: 'x') }
        .to raise_error(described_class::ApiKeyMissingError)
    end

    it 'validates the description before calling the LLM' do
      expect(adapter).not_to receive(:generate)
      expect { described_class.generate_definition(description: '') }
        .to raise_error(described_class::GenerationError)
    end
  end
end
