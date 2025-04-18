# File: spec/adk/tools/calculator_spec.rb
require 'spec_helper'

RSpec.describe ADK::Tools::Calculator do
  subject(:tool) { described_class.new }

  describe '#initialize' do
    it 'sets the name correctly' do
      expect(tool.name).to eq(:calculator)
    end

    it 'sets the description correctly' do
      expect(tool.description).to include('Calculates the result of an arithmetic operation')
    end

    it 'defines parameters' do
      expect(tool.parameters.keys).to contain_exactly(:operand1, :operand2, :operation)
      expect(tool.parameters[:operand1][:required]).to eq(true)
      expect(tool.parameters[:operand2][:required]).to eq(true)
      expect(tool.parameters[:operation][:required]).to eq(true)
    end
  end

  describe '#execute' do
    context 'with valid parameters for addition' do
      let(:params) { { operand1: '5', operand2: '3.5', operation: 'add' } } # Params often come as strings from web/cli

      it 'returns a success hash with the correct sum' do
        result = tool.execute(params)
        expect(result[:status]).to eq(:success)
        expect(result[:result]).to eq(8.5)
      end
    end

    context 'with valid parameters for subtraction' do
      let(:params) { { operand1: 10, operand2: 4, operation: 'subtract' } } # Test with numbers too

      it 'returns a success hash with the correct difference' do
        result = tool.execute(params)
        expect(result).to eq({ status: :success, result: 6.0 })
      end
    end

    context 'with valid parameters for multiplication' do
      let(:params) { { operand1: 6, operand2: 7, operation: '*' } } # Test symbol op

      it 'returns a success hash with the correct product' do
        result = tool.execute(params)
        expect(result).to eq({ status: :success, result: 42.0 })
      end
    end

    context 'with valid parameters for division' do
      let(:params) { { operand1: 10.0, operand2: 4, operation: '/' } }

      it 'returns a success hash with the correct quotient' do
        result = tool.execute(params)
        expect(result).to eq({ status: :success, result: 2.5 })
      end
    end

    context 'with division by zero' do
      let(:params) { { operand1: 10, operand2: 0, operation: 'divide' } }

      it 'returns an error hash' do
        result = tool.execute(params)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to match(/Division by zero/i)
      end
    end

    context 'with an unsupported operation' do
      let(:params) { { operand1: 10, operand2: 5, operation: 'modulo' } }

      it 'returns an error hash' do
        result = tool.execute(params)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to match(/Unsupported operation: 'modulo'/i)
      end
    end

    context 'with non-numeric input for operands' do
      let(:params) { { operand1: 'ten', operand2: 5, operation: 'add' } }

      it 'returns an error hash' do
        result = tool.execute(params)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to match(/Invalid numeric input/i)
      end
    end

    # Test base class validation triggering
    context 'with missing required parameters' do
      let(:params) { { operand1: 10, operation: 'add' } } # Missing operand2

      it 'raises an ADK::Error' do
        expect { tool.execute(params) }.to raise_error(ADK::Error, /Missing required parameters: operand2/)
      end
    end
  end
end
