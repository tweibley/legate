# frozen_string_literal: true

require 'spec_helper'
require 'legate/tool_result'

RSpec.describe Legate::ToolResult do
  describe 'factories, predicates, and #to_h' do
    it 'builds a success carrying a value' do
      r = described_class.success('hi')
      expect(r.success?).to be true
      expect(r.error?).to be false
      expect(r.to_h).to eq(status: :success, result: 'hi')
    end

    it 'allows a success with no value' do
      expect(described_class.success.to_h).to eq(status: :success, result: nil)
    end

    it 'builds an error' do
      r = described_class.error('boom')
      expect(r.error?).to be true
      expect(r.to_h).to eq(status: :error, error_message: 'boom')
    end

    it 'builds a pending result, with and without a message' do
      expect(described_class.pending(job_id: 'j1').to_h).to eq(status: :pending, job_id: 'j1')
      expect(described_class.pending(job_id: 'j1', message: 'queued').to_h)
        .to eq(status: :pending, job_id: 'j1', message: 'queued')
    end

    it 'is immutable (a Data value object)' do
      expect(described_class.success('x')).to be_frozen
    end
  end
end
