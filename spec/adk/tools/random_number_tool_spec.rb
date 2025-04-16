# File: spec/adk/tools/random_number_tool_spec.rb
require 'spec_helper'

RSpec.describe ADK::Tools::RandomNumberTool do
  subject(:tool) { described_class.new }

  describe '#initialize' do
    it 'sets the name correctly' do
      expect(tool.name).to eq(:random_number)
    end

    it 'sets the description correctly' do
      expect(tool.description).to include('Generates a random integer')
    end

    it 'defines optional parameters :min and :max' do
      expect(tool.parameters.keys).to contain_exactly(:min, :max)
      expect(tool.parameters[:min][:required]).to eq(false)
      expect(tool.parameters[:max][:required]).to eq(false)
      expect(tool.parameters[:min][:type]).to eq(:integer)
      expect(tool.parameters[:max][:type]).to eq(:integer)
    end
  end

  describe '#execute' do
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

      it 'returns an error hash' do
        result = tool.execute(params)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to match(/Min value \(100\) cannot be greater than Max value \(90\)/)
      end
    end

    context 'with non-integer input for min' do
      let(:params) { { min: 'abc', max: 100 } }

      it 'returns an error hash' do
        result = tool.execute(params)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to match(/Invalid integer input.*Min: 'abc'/)
      end
    end

    context 'with non-integer input for max' do
      let(:params) { { min: 1, max: 'xyz' } }

      it 'returns an error hash' do
        result = tool.execute(params)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to match(/Invalid integer input.*Max: 'xyz'/)
      end
    end

    # Note: Base class validation (missing required) isn't applicable here as params are optional
  end
end
