# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool do
  let(:tool_class) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :coercion_test
      tool_description 'Test'
      parameter :bool_val, type: :boolean
      parameter :int_val, type: :integer
      parameter :array_val, type: :array
      parameter :hash_val, type: :hash

      def perform_execution(params, _context)
        { status: :success, result: params }
      end
    end
  end
  let(:tool) { tool_class.new }

  describe '#validate_and_coerce_params' do
    context 'boolean coercion' do
      it 'coerces truthy string values' do
        %w[true t yes 1 True YES].each do |val|
          expect(tool.validate_and_coerce_params(bool_val: val)[:bool_val]).to be(true)
        end
      end

      it 'coerces falsy string values' do
        %w[false f no 0 False NO].each do |val|
          expect(tool.validate_and_coerce_params(bool_val: val)[:bool_val]).to be(false)
        end
      end

      it 'raises error for invalid boolean strings' do
        expect { tool.validate_and_coerce_params(bool_val: 'invalid') }
          .to raise_error(ADK::ToolArgumentError, /expected Boolean/)
      end
    end

    context 'numeric coercion' do
      it 'coerces strings to integers' do
        expect(tool.validate_and_coerce_params(int_val: '123')[:int_val]).to eq(123)
      end

      it 'raises error for invalid integer strings' do
        expect { tool.validate_and_coerce_params(int_val: 'abc') }
          .to raise_error(ADK::ToolArgumentError, /expected Integer/)
      end
    end

    context 'json coercion' do
      it 'parses JSON strings for arrays' do
        expect(tool.validate_and_coerce_params(array_val: '["a"]')[:array_val]).to eq(['a'])
      end

      it 'parses JSON strings for hashes' do
        expect(tool.validate_and_coerce_params(hash_val: '{"k":"v"}')[:hash_val]).to eq({ 'k' => 'v' })
      end

      it 'raises error for malformed JSON' do
        expect { tool.validate_and_coerce_params(array_val: 'not json') }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end
    end
  end
end
