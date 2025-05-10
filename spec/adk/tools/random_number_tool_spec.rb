# frozen_string_literal: true
# File: spec/adk/tools/random_number_tool_spec.rb
require 'spec_helper'

RSpec.describe ADK::Tools::RandomNumberTool do
  let(:tool_class) { described_class }
  let(:metadata) { tool_class.tool_metadata }

  # Test Class Metadata directly
  describe 'Class Metadata' do
    it 'has the correct explicit name' do
      expect(metadata[:name]).to eq(:random_number)
    end

    it 'has the correct description' do
      expect(metadata[:description]).to include('Generates a random integer')
    end

    it 'defines optional parameters :min and :max correctly' do
      expect(metadata[:parameters].keys).to contain_exactly(:min, :max)
      expect(metadata[:parameters][:min][:required]).to eq(false)
      expect(metadata[:parameters][:max][:required]).to eq(false)
      expect(metadata[:parameters][:min][:type]).to eq(:integer)
      expect(metadata[:parameters][:max][:type]).to eq(:integer)
    end
  end

  describe '#execute' do
    subject(:tool) { tool_class.new } # Create instance for execution tests

    context 'with default parameters' do
      it 'returns a success hash with an integer between 1 and 100' do
        # Allow rand to work normally but check range
        result = tool.execute({})
        expect(result[:status]).to eq(:success)
        expect(result[:result]).to be_an(Integer)
        expect(result[:result]).to be >= 1
        expect(result[:result]).to be <= 100
      end

      it 'uses the default range 1..100 for rand' do
        # Mock rand specifically for this test
        expect(tool).to receive(:rand).with(1..100).and_return(42)
        result = tool.execute({})
        expect(result).to eq({ status: :success, result: 42 })
      end
    end

    context 'with valid min and max parameters' do
      let(:params) { { min: '10', max: '15' } } # Use strings like from web/cli

      it 'returns a success hash with an integer within the specified range' do
        expect(tool).to receive(:rand).with(10..15).and_return(12)
        result = tool.execute(params)
        expect(result).to eq({ status: :success, result: 12 })
      end
    end

    context 'with symbolic keys for min and max parameters' do
      let(:params) { { min: 50, max: 55 } } # Use symbols/integers

      it 'returns a success hash with an integer within the specified range' do
        expect(tool).to receive(:rand).with(50..55).and_return(53)
        result = tool.execute(params)
        expect(result).to eq({ status: :success, result: 53 })
      end
    end

    context 'with min greater than max' do
      let(:params) { { min: 100, max: 90 } }

      it 'raises ToolArgumentError' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolArgumentError, /Min value \(100\) cannot be greater than Max value \(90\)/)
      end
    end

    context 'with non-integer input for min' do
      let(:params) { { min: 'abc', max: 100 } }

      it 'raises ToolArgumentError' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolArgumentError, /Invalid integer input.*Min: 'abc'/)
      end
    end

    context 'with non-integer input for max' do
      let(:params) { { min: 1, max: 'xyz' } }

      it 'raises ToolArgumentError' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolArgumentError, /Invalid integer input.*Max: 'xyz'/)
      end
    end

    # Note: Base class validation (missing required) isn't applicable here as params are optional
  end
end
