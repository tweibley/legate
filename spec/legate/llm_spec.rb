# frozen_string_literal: true

require 'spec_helper'
require 'legate/llm'

RSpec.describe Legate::LLM do
  describe '.build_adapter' do
    around do |example|
      saved = described_class.default_adapter_factory
      example.run
      described_class.default_adapter_factory = saved
    end

    it 'builds a Gemini adapter by default' do
      described_class.default_adapter_factory = nil
      allow(Gemini).to receive(:new).and_return(double('client'))
      adapter = described_class.build_adapter(model: 'gemini-2.0-flash', api_key: 'k')
      expect(adapter).to be_a(Legate::LLM::Gemini)
    end

    it 'uses the configured factory when set (any provider)' do
      custom = instance_double(Legate::LLM::Adapter)
      described_class.default_adapter_factory = lambda { |model:, api_key:, logger:|
        expect(model).to eq('llama3')
        custom
      }
      expect(described_class.build_adapter(model: 'llama3', api_key: nil, logger: nil)).to eq(custom)
    end
  end
end
