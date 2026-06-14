# frozen_string_literal: true

require 'spec_helper'
require 'legate/planner'

RSpec.describe Legate::Planner, '#reason_next_action' do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:definition) { instance_double(Legate::AgentDefinition) }
  let(:agent) do
    instance_double(
      Legate::Agent,
      name: :researcher,
      instruction: 'Find the answer.',
      before_model_callback: nil,
      definition: definition,
      available_tools_metadata: [{ name: :search }, { name: :echo }]
    )
  end
  # JSON-prompt path: an adapter without native function calling (Ollama-like).
  let(:adapter) do
    instance_double(Legate::LLM::Gemini, available?: true, model_name: 'gemini-2.0-flash',
                                         supports_function_calling?: false)
  end
  subject(:planner) { described_class.new(agent: agent, logger: logger, llm_adapter: adapter) }

  before do
    allow(definition).to receive(:respond_to?).with(:delegation_targets).and_return(false)
    # Tool-catalog formatting is exercised by the planner's own specs; here we
    # focus on the reason/decision logic.
    allow_any_instance_of(described_class).to receive(:format_tools_for_prompt).and_return('Tool descriptions')
  end

  it 'returns a tool decision when the model picks a tool' do
    allow(adapter).to receive(:generate).and_return(
      '{"thought":"search first","action":"tool","tool_name":"search","tool_input":{"q":"ruby"}}'
    )
    decision = planner.reason_next_action('find ruby info', [])
    expect(decision.tool?).to be true
    expect(decision.tool).to eq(:search)
    expect(decision.params).to eq(q: 'ruby')
  end

  it 'returns a final decision when the model is done' do
    allow(adapter).to receive(:generate).and_return('{"action":"final","answer":"42"}')
    decision = planner.reason_next_action('the answer?', [])
    expect(decision.final?).to be true
    expect(decision.answer).to eq('42')
  end

  it 'rejects an unknown tool name (Symbol-DoS guard) as invalid' do
    allow(adapter).to receive(:generate).and_return(
      '{"action":"tool","tool_name":"rm_rf","tool_input":{}}'
    )
    expect(planner.reason_next_action('x', []).invalid?).to be true
  end

  it 'treats unparseable output as invalid' do
    allow(adapter).to receive(:generate).and_return('not json at all')
    expect(planner.reason_next_action('x', []).invalid?).to be true
  end

  it 'feeds observations into the prompt' do
    observations = [{ tool: :search, params: { q: 'ruby' }, result: { status: :success, result: 'docs' } }]
    expect(adapter).to receive(:generate) do |prompt, **_|
      expect(prompt).to include('Step 1: called `search')
      expect(prompt).to include('docs')
      '{"action":"final","answer":"ok"}'
    end
    planner.reason_next_action('find ruby info', observations)
  end

  it 'finishes gracefully when the adapter is unavailable' do
    down = instance_double(Legate::LLM::Gemini, available?: false, model_name: nil)
    p = described_class.new(agent: agent, logger: logger, llm_adapter: down)
    expect(p.reason_next_action('x', []).final?).to be true
  end

  describe '#summarize_final' do
    let(:observations) { [{ tool: :search, params: { q: 'ruby' }, result: { status: :success, result: 'docs' } }] }

    it 'asks the model for a best-effort answer from the observations (plain text, no JSON)' do
      expect(adapter).to receive(:generate) do |prompt, **opts|
        expect(opts[:json]).to be_falsey
        expect(prompt).to include('best final answer')
        expect(prompt).to include('Step 1: called `search')
        '  Ruby is great.  '
      end
      expect(planner.summarize_final('tell me about ruby', observations)).to eq('Ruby is great.')
    end

    it 'returns nil when the adapter is unavailable' do
      down = instance_double(Legate::LLM::Gemini, available?: false, model_name: nil)
      p = described_class.new(agent: agent, logger: logger, llm_adapter: down)
      expect(p.summarize_final('x', observations)).to be_nil
    end

    it 'returns nil (does not raise) when the model call fails' do
      allow(adapter).to receive(:generate).and_raise(StandardError, 'boom')
      expect(planner.summarize_final('x', observations)).to be_nil
    end
  end

  describe 'native function-calling path' do
    # An adapter that advertises native function calling -> reason_next_action
    # routes through #generate_with_tools instead of the JSON prompt.
    let(:fc_adapter) do
      instance_double(Legate::LLM::Gemini, available?: true, model_name: 'gemini-2.0-flash',
                                           supports_function_calling?: true)
    end
    subject(:fc_planner) { described_class.new(agent: agent, logger: logger, llm_adapter: fc_adapter) }

    it 'passes the agent tool schemas to the adapter and maps a tool choice to a Decision' do
      expect(fc_adapter).to receive(:generate_with_tools) do |_prompt, tools:|
        expect(tools.map { |t| t[:name] }).to include('search', 'echo')
        { kind: :tool, name: 'search', arguments: { 'q' => 'ruby' }, thought: 'look it up' }
      end
      decision = fc_planner.reason_next_action('find ruby info', [])
      expect(decision.tool?).to be true
      expect(decision.tool).to eq(:search)
      expect(decision.params).to eq(q: 'ruby')
    end

    it 'maps a final choice to a final Decision' do
      allow(fc_adapter).to receive(:generate_with_tools).and_return({ kind: :final, text: '42', thought: nil })
      decision = fc_planner.reason_next_action('the answer?', [])
      expect(decision.final?).to be true
      expect(decision.answer).to eq('42')
    end

    it 'maps Legate parameter types to valid JSON Schema types in the tool schemas' do
      allow(agent).to receive(:available_tools_metadata).and_return(
        [{ name: :calc, description: 'c',
           parameters: { amount: { type: :float, required: true, description: 'n' },
                         opts: { type: :hash, required: false, description: 'o' },
                         tags: { type: :array, required: false, description: 't' } } }]
      )
      captured = nil
      allow(fc_adapter).to receive(:generate_with_tools) do |_prompt, tools:|
        captured = tools
        { kind: :final, text: 'ok', thought: nil }
      end
      fc_planner.reason_next_action('x', [])

      props = captured.first[:parameters][:properties]
      expect(props[:amount][:type]).to eq('number') # :float -> number, not "FLOAT"
      expect(props[:opts][:type]).to eq('object') # :hash  -> object
      expect(props[:tags][:type]).to eq('array')
      expect(captured.first[:parameters][:required]).to eq([:amount])
    end

    it 'rejects an unknown tool name (Symbol-DoS guard) as invalid' do
      allow(fc_adapter).to receive(:generate_with_tools).and_return({ kind: :tool, name: 'rm_rf', arguments: {} })
      expect(fc_planner.reason_next_action('x', []).invalid?).to be true
    end

    it 'does not call #generate on the JSON path' do
      allow(fc_adapter).to receive(:generate_with_tools).and_return({ kind: :final, text: 'done', thought: nil })
      expect(fc_adapter).not_to receive(:generate)
      fc_planner.reason_next_action('x', [])
    end
  end
end
