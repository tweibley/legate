# File: spec/legate/tools/current_time_tool_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/tools/current_time_tool'

RSpec.describe Legate::Tools::CurrentTime do
  let(:tool) { described_class.new }
  let(:context) { Object.new }

  def run(params = {})
    tool.send(:perform_execution, params, context)
  end

  it 'has the inferred tool name :current_time' do
    expect(described_class.tool_metadata[:name]).to eq(:current_time)
  end

  it 'returns UTC ISO 8601, formatted, and epoch by default' do
    result = run
    expect(result[:status]).to eq(:success)
    expect(result[:result][:timezone]).to eq('UTC')
    expect(result[:result][:iso8601]).to match(/\AZ?|.*Z\z/)
    expect(result[:result][:iso8601]).to end_with('Z')
    expect(result[:result][:epoch]).to be_a(Integer)
    expect(result[:result][:formatted]).to eq(result[:result][:iso8601])
  end

  it 'applies a custom strftime format' do
    result = run(format: '%Y-%m-%d')
    expect(result[:result][:formatted]).to match(/\A\d{4}-\d{2}-\d{2}\z/)
  end

  it 'applies a fixed UTC offset' do
    result = run(timezone: '+09:00')
    expect(result[:status]).to eq(:success)
    expect(result[:result][:iso8601]).to end_with('+09:00')
  end

  it 'supports the local timezone' do
    result = run(timezone: 'local')
    expect(result[:status]).to eq(:success)
  end

  it 'rejects named IANA timezones with a helpful message' do
    result = run(timezone: 'America/New_York')
    expect(result[:status]).to eq(:error)
    expect(result[:error_message]).to match(/Unsupported timezone.*fixed offset/)
  end

  it 'agrees that UTC and a +00:00 offset describe the same instant' do
    epoch_utc = run[:result][:epoch]
    epoch_offset = run(timezone: '+00:00')[:result][:epoch]
    expect((epoch_utc - epoch_offset).abs).to be <= 1
  end
end
