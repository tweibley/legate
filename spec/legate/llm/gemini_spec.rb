# frozen_string_literal: true

require 'spec_helper'
require 'legate/llm/gemini'

RSpec.describe Legate::LLM::Gemini do
  let(:mock_client) { double('Gemini') }
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }

  def gemini_response(text)
    { 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => text }] } }] }
  end

  describe '#available?' do
    it 'is false (and logs) without an API key' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(nil)
      allow(ENV).to receive(:[]).with('GEMINI_API_KEY').and_return(nil)
      adapter = described_class.new(model: 'gemini-2.0-flash', api_key: nil, logger: logger)
      expect(adapter.available?).to be false
      expect(adapter.model_name).to be_nil
    end

    it 'accepts GEMINI_API_KEY directly when GOOGLE_API_KEY is unset' do
      allow(Gemini).to receive(:new).and_return(mock_client)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(nil)
      allow(ENV).to receive(:[]).with('GEMINI_API_KEY').and_return('gem-key')
      adapter = described_class.new(model: 'gemini-2.0-flash', api_key: nil, logger: logger)
      expect(adapter.available?).to be true
    end

    it 'is true when the client constructs' do
      allow(Gemini).to receive(:new).and_return(mock_client)
      adapter = described_class.new(model: 'gemini-2.0-flash', api_key: 'k', logger: logger)
      expect(adapter.available?).to be true
      expect(adapter.model_name).to eq('gemini-2.0-flash')
    end

    it 'is false when client construction raises' do
      allow(Gemini).to receive(:new).and_raise(StandardError, 'boom')
      adapter = described_class.new(model: 'gemini-2.0-flash', api_key: 'k', logger: logger)
      expect(adapter.available?).to be false
    end
  end

  describe '#generate' do
    subject(:adapter) { described_class.new(model: 'gemini-2.0-flash', api_key: 'k', logger: logger) }

    before { allow(Gemini).to receive(:new).and_return(mock_client) }

    it 'returns the response text' do
      allow(mock_client).to receive(:generate_content).and_return(gemini_response('{"ok":true}'))
      expect(adapter.generate('hi', json: true)).to eq('{"ok":true}')
    end

    it 'requests JSON output when json: true' do
      expect(mock_client).to receive(:generate_content).with(
        hash_including(generationConfig: { responseMimeType: 'application/json' })
      ).and_return(gemini_response('{}'))
      adapter.generate('hi', json: true)
    end

    it 'omits the JSON config when json: false' do
      expect(mock_client).to receive(:generate_content).with(
        hash_excluding(:generationConfig)
      ).and_return(gemini_response('text'))
      adapter.generate('hi', json: false)
    end

    it 'sends a responseSchema for structured output when schema: is given' do
      schema = { type: 'OBJECT', properties: { x: { type: 'STRING' } } }
      expect(mock_client).to receive(:generate_content) do |payload|
        expect(payload[:generationConfig][:responseMimeType]).to eq('application/json')
        expect(payload[:generationConfig][:responseSchema]).to eq(schema)
        gemini_response('{"x":"y"}')
      end
      adapter.generate('hi', json: true, schema: schema)
    end

    it 'returns nil when unavailable' do
      allow(Gemini).to receive(:new).and_raise(StandardError, 'boom')
      down = described_class.new(model: 'gemini-2.0-flash', api_key: 'k', logger: logger)
      expect(down.generate('hi')).to be_nil
    end

    it 'retries a retryable error then succeeds' do
      call_count = 0
      allow(mock_client).to receive(:generate_content) do
        call_count += 1
        raise Net::ReadTimeout if call_count == 1

        gemini_response('{"ok":1}')
      end
      allow(adapter).to receive(:sleep) # don't actually wait
      expect(adapter.generate('hi', json: true)).to eq('{"ok":1}')
      expect(call_count).to eq(2)
    end

    it 'does not retry a non-retryable error' do
      allow(mock_client).to receive(:generate_content).and_raise(ArgumentError, 'bad request')
      expect { adapter.generate('hi') }.to raise_error(ArgumentError)
    end
  end

  describe '#supports_function_calling?' do
    it 'is true (Gemini v1beta supports native function calling)' do
      allow(Gemini).to receive(:new).and_return(mock_client)
      adapter = described_class.new(model: 'gemini-2.0-flash', api_key: 'k', logger: logger)
      expect(adapter.supports_function_calling?).to be true
    end
  end

  describe '#supports_structured_output?' do
    it 'is true (Gemini supports responseSchema)' do
      allow(Gemini).to receive(:new).and_return(mock_client)
      adapter = described_class.new(model: 'gemini-2.0-flash', api_key: 'k', logger: logger)
      expect(adapter.supports_structured_output?).to be true
    end
  end

  describe '#generate_with_tools' do
    subject(:adapter) { described_class.new(model: 'gemini-2.0-flash', api_key: 'k', logger: logger) }

    let(:tools) do
      [{ name: :search, description: 'Web search',
         parameters: { properties: { q: { type: :string, description: 'query' } }, required: [:q] } }]
    end

    before { allow(Gemini).to receive(:new).and_return(mock_client) }

    def function_call_response(name, args)
      { 'candidates' => [{ 'content' => { 'parts' => [{ 'functionCall' => { 'name' => name, 'args' => args } }] } }] }
    end

    it 'sends functionDeclarations built from the tool schemas (OpenAPI types)' do
      expect(mock_client).to receive(:generate_content) do |payload|
        decl = payload.dig(:tools, 0, :functionDeclarations, 0)
        expect(decl[:name]).to eq('search')
        expect(decl[:parameters][:type]).to eq('OBJECT')
        expect(decl[:parameters][:properties][:q][:type]).to eq('STRING')
        expect(decl[:parameters][:required]).to eq(['q'])
        function_call_response('search', { 'q' => 'ruby' })
      end
      adapter.generate_with_tools('do it', tools: tools)
    end

    it 'maps a functionCall part to a :tool choice' do
      allow(mock_client).to receive(:generate_content).and_return(function_call_response('search', { 'q' => 'ruby' }))
      choice = adapter.generate_with_tools('do it', tools: tools)
      expect(choice).to include(kind: :tool, name: 'search', arguments: { 'q' => 'ruby' })
    end

    it 'maps a text-only response to a :final choice' do
      allow(mock_client).to receive(:generate_content).and_return(gemini_response('here is the answer'))
      choice = adapter.generate_with_tools('do it', tools: tools)
      expect(choice).to include(kind: :final, text: 'here is the answer')
    end

    it 'returns a :final choice with nil text when unavailable' do
      allow(Gemini).to receive(:new).and_raise(StandardError, 'boom')
      down = described_class.new(model: 'gemini-2.0-flash', api_key: 'k', logger: logger)
      expect(down.generate_with_tools('x', tools: tools)).to eq(kind: :final, text: nil, thought: nil)
    end
  end
end
