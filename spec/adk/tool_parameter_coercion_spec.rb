# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool'

RSpec.describe ADK::Tool do
  let(:tool) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :coercion_test
      tool_description 'Tests parameter coercion'

      parameter :int_p, type: :integer
      parameter :float_p, type: :float
      parameter :bool_p, type: :boolean
      parameter :array_p, type: :array
      parameter :hash_p, type: :hash
      parameter :any_p, type: :any

      def perform_execution(params, context); end
    end.new
  end

  describe '#validate_and_coerce_params' do
    it 'coerces valid string inputs to correct types' do
      result = tool.validate_and_coerce_params(
        int_p: '42',
        float_p: '3.14',
        bool_p: 'true',
        array_p: '[1, 2]',
        hash_p: '{"key": "value"}'
      )

      expect(result).to include(
        int_p: 42,
        float_p: 3.14,
        bool_p: true,
        array_p: [1, 2],
        hash_p: { 'key' => 'value' }
      )
    end

    it 'handles boolean variations correctly' do
      expect(tool.validate_and_coerce_params(bool_p: 'yes')[:bool_p]).to be true
      expect(tool.validate_and_coerce_params(bool_p: '1')[:bool_p]).to be true
      expect(tool.validate_and_coerce_params(bool_p: 'no')[:bool_p]).to be false
      expect(tool.validate_and_coerce_params(bool_p: '0')[:bool_p]).to be false
    end

    it 'leaves already correct types as is' do
      result = tool.validate_and_coerce_params(
        int_p: 10,
        bool_p: false,
        array_p: ['a'],
        hash_p: { a: 1 }
      )
      expect(result).to include(int_p: 10, bool_p: false, array_p: ['a'], hash_p: { a: 1 })
    end

    it 'leaves nil values as nil' do
      expect(tool.validate_and_coerce_params(int_p: nil)[:int_p]).to be_nil
    end

    it 'raises ToolArgumentError for invalid inputs' do
      expect { tool.validate_and_coerce_params(int_p: 'not_an_int') }.to raise_error(ADK::ToolArgumentError)
      expect { tool.validate_and_coerce_params(bool_p: 'maybe') }.to raise_error(ADK::ToolArgumentError)
      expect { tool.validate_and_coerce_params(array_p: 'not_array') }.to raise_error(ADK::ToolArgumentError)
      expect { tool.validate_and_coerce_params(hash_p: '[]') }.to raise_error(ADK::ToolArgumentError)
    end
  end
end
