# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool, 'Coercion' do
  let(:tool) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :coercion_test
      parameter :int, type: :integer
      parameter :bool, type: :boolean
      parameter :arr, type: :array

      def perform_execution(params, _context)
        { status: :success, result: params }
      end
    end.new
  end

  describe '#validate_and_coerce_params' do
    it 'coerces boolean strings correctly' do
      expect(tool.validate_and_coerce_params(bool: 'true')[:bool]).to be true
      expect(tool.validate_and_coerce_params(bool: 'no')[:bool]).to be false
    end

    it 'coerces integer strings correctly' do
      expect(tool.validate_and_coerce_params(int: '42')[:int]).to eq(42)
      expect { tool.validate_and_coerce_params(int: 'invalid') }
        .to raise_error(ADK::ToolArgumentError)
    end

    it 'coerces JSON strings to arrays' do
      expect(tool.validate_and_coerce_params(arr: '[1, 2]')[:arr]).to eq([1, 2])
      expect { tool.validate_and_coerce_params(arr: 'not_json') }
        .to raise_error(ADK::ToolArgumentError)
    end
  end
end
