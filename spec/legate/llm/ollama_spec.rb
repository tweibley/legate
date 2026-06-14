# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'legate/llm/ollama'

RSpec.describe Legate::LLM::Ollama do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:host) { 'http://localhost:11434' }
  subject(:adapter) { described_class.new(model: 'llama3', host: host, logger: logger) }

  describe '#available? / #model_name' do
    it 'is available (local) and reports its model' do
      expect(adapter.available?).to be true
      expect(adapter.model_name).to eq('llama3')
    end

    it 'defaults the host to OLLAMA_HOST then localhost:11434' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('OLLAMA_HOST').and_return(nil)
      a = described_class.new(model: 'llama3', logger: logger)
      expect(a.instance_variable_get(:@host)).to eq('http://localhost:11434')
    end
  end

  describe '#generate' do
    it 'POSTs to /api/generate and returns the response text' do
      stub = stub_request(:post, "#{host}/api/generate")
             .with(body: hash_including('model' => 'llama3', 'prompt' => 'hello', 'stream' => false))
             .to_return(status: 200, body: { response: '{"ok":true}', done: true }.to_json)

      expect(adapter.generate('hello')).to eq('{"ok":true}')
      expect(stub).to have_been_requested
    end

    it 'requests JSON-constrained output when json: true' do
      stub = stub_request(:post, "#{host}/api/generate")
             .with(body: hash_including('format' => 'json'))
             .to_return(status: 200, body: { response: '{}' }.to_json)

      adapter.generate('hello', json: true)
      expect(stub).to have_been_requested
    end

    it 'omits format when json: false' do
      stub_request(:post, "#{host}/api/generate")
        .to_return(status: 200, body: { response: 'plain' }.to_json)

      adapter.generate('hello', json: false)
      expect(a_request(:post, "#{host}/api/generate")
        .with { |req| !JSON.parse(req.body).key?('format') }).to have_been_made
    end

    it 'raises (and logs) on a non-success HTTP status' do
      stub_request(:post, "#{host}/api/generate").to_return(status: 500, body: 'boom')
      expect(logger).to receive(:error).with(/Ollama generate failed/)
      expect { adapter.generate('hello') }.to raise_error(/Ollama HTTP 500/)
    end
  end
end
