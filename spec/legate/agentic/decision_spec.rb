# frozen_string_literal: true

require 'spec_helper'
require 'legate/agentic/decision'

RSpec.describe Legate::Agentic::Decision do
  describe '.tool' do
    subject(:d) { described_class.tool(tool: 'search', params: { q: 'x' }, thought: 'looking') }

    it 'is a tool decision with a symbol tool and a step shape' do
      expect(d.tool?).to be true
      expect(d.final?).to be false
      expect(d.invalid?).to be false
      expect(d.tool).to eq(:search)
      expect(d.to_step).to eq(tool: :search, params: { q: 'x' })
    end
  end

  describe '.final' do
    subject(:d) { described_class.final(answer: 'done') }

    it 'is a final decision' do
      expect(d.final?).to be true
      expect(d.tool?).to be false
      expect(d.invalid?).to be false
      expect(d.answer).to eq('done')
    end
  end

  describe '.invalid' do
    it 'is neither tool nor final' do
      d = described_class.invalid
      expect(d.invalid?).to be true
      expect(d.final?).to be false
      expect(d.tool?).to be false
    end
  end
end
