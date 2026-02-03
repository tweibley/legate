# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool do
  let(:coercion_tool_class) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :coercion_test_tool
      tool_description 'Tool for testing parameter coercion'

      parameter :bool_val, type: :boolean
      parameter :int_val, type: :integer
      parameter :float_val, type: :float
      parameter :array_val, type: :array
      parameter :hash_val, type: :hash

      def perform_execution(params, context); end
    end
  end

  subject(:tool) { coercion_tool_class.new }

  describe 'parameter coercion' do
    describe 'boolean coercion' do
      it 'coerces truthy strings to true' do
        %w[true t yes 1 TRUE True].each do |val|
          params = tool.validate_and_coerce_params(bool_val: val)
          expect(params[:bool_val]).to be(true)
        end
      end

      it 'coerces falsy strings to false' do
        %w[false f no 0 FALSE False].each do |val|
          params = tool.validate_and_coerce_params(bool_val: val)
          expect(params[:bool_val]).to be(false)
        end
      end

      it 'raises error for invalid boolean strings' do
        expect { tool.validate_and_coerce_params(bool_val: 'maybe') }
          .to raise_error(ADK::ToolArgumentError, /expected Boolean/)
      end
    end

    describe 'JSON coercion (Array)' do
      it 'parses valid JSON arrays' do
        params = tool.validate_and_coerce_params(array_val: '[1, "a", true]')
        expect(params[:array_val]).to eq([1, 'a', true])
      end

      it 'accepts Ruby arrays directly' do
        params = tool.validate_and_coerce_params(array_val: [1, 2])
        expect(params[:array_val]).to eq([1, 2])
      end

      it 'raises error for non-array JSON' do
        expect { tool.validate_and_coerce_params(array_val: '{"a": 1}') }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end

      it 'raises error for invalid JSON' do
        expect { tool.validate_and_coerce_params(array_val: '[unclosed') }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end
    end

    describe 'JSON coercion (Hash)' do
      it 'parses valid JSON hashes' do
        params = tool.validate_and_coerce_params(hash_val: '{"key": "value"}')
        expect(params[:hash_val]).to eq({ 'key' => 'value' })
      end

      it 'accepts Ruby hashes directly' do
        params = tool.validate_and_coerce_params(hash_val: { a: 1 })
        expect(params[:hash_val]).to eq({ a: 1 })
      end

      it 'raises error for non-hash JSON' do
        expect { tool.validate_and_coerce_params(hash_val: '[1, 2]') }
          .to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end
    end

    describe 'Numeric coercion' do
      it 'coerces string to integer' do
        expect(tool.validate_and_coerce_params(int_val: '42')[:int_val]).to eq(42)
      end

      it 'coerces string to float' do
        expect(tool.validate_and_coerce_params(float_val: '3.14')[:float_val]).to eq(3.14)
      end

      it 'raises error for invalid integer' do
        expect { tool.validate_and_coerce_params(int_val: 'not-a-number') }
          .to raise_error(ADK::ToolArgumentError, /expected Integer/)
      end

      it 'raises error for invalid float' do
        expect { tool.validate_and_coerce_params(float_val: 'not-a-number') }
          .to raise_error(ADK::ToolArgumentError, /expected Numeric/)
      end
    end
  end
end
