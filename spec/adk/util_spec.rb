# frozen_string_literal: true

require 'spec_helper'
require 'adk/util'

RSpec.describe ADK::Util do
  describe '.deep_copy' do
    it 'returns a copy of a hash' do
      original = { a: 1, b: 2 }
      copy = described_class.deep_copy(original)
      expect(copy).to eq(original)
      expect(copy).not_to be(original)
    end

    it 'deep copies nested hashes' do
      original = { a: { b: 2 } }
      copy = described_class.deep_copy(original)
      expect(copy).to eq(original)
      expect(copy[:a]).not_to be(original[:a])
    end

    it 'returns a copy of an array' do
      original = [1, 2, 3]
      copy = described_class.deep_copy(original)
      expect(copy).to eq(original)
      expect(copy).not_to be(original)
    end

    it 'deep copies nested arrays' do
      original = [[1], [2]]
      copy = described_class.deep_copy(original)
      expect(copy).to eq(original)
      expect(copy[0]).not_to be(original[0])
    end

    it 'returns a copy of a string' do
      original = 'test'
      copy = described_class.deep_copy(original)
      expect(copy).to eq(original)
      expect(copy).not_to be(original)
    end

    it 'returns immediate values as is' do
      expect(described_class.deep_copy(1)).to eq(1)
      expect(described_class.deep_copy(:symbol)).to eq(:symbol)
      expect(described_class.deep_copy(true)).to eq(true)
      expect(described_class.deep_copy(nil)).to eq(nil)
    end

    it 'preserves symbols in hashes' do
      original = { a: :b, c: 'd' }
      copy = described_class.deep_copy(original)
      expect(copy.keys).to all(be_a(Symbol))
      expect(copy[:a]).to be_a(Symbol)
    end

    it 'handles mixed structures' do
      original = {
        a: [1, { b: 'c' }],
        d: { e: [2, 3] }
      }
      copy = described_class.deep_copy(original)
      expect(copy).to eq(original)

      # Verify deep copy nature
      copy[:a][1][:b] = 'changed'
      expect(original[:a][1][:b]).to eq('c')
    end
  end
end
