# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool'

RSpec.describe 'ADK::Tool Coercion' do
  let(:tool_class) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :coercion_test_tool
      tool_description 'A tool for testing coercion'

      parameter :string_param, type: :string
      parameter :integer_param, type: :integer
      parameter :float_param, type: :float
      parameter :boolean_param, type: :boolean
      parameter :array_param, type: :array
      parameter :hash_param, type: :hash
      parameter :any_param # No type defined

      def perform_execution(params, _context)
        { status: :success, result: params }
      end
    end
  end

  let(:tool) { tool_class.new }
  let(:context) { instance_double('ADK::ToolContext') }

  describe '#validate_and_coerce_params' do
    context 'Integer coercion' do
      it 'coerces string integer to Integer' do
        result = tool.validate_and_coerce_params(integer_param: '123')
        expect(result[:integer_param]).to eq(123)
        expect(result[:integer_param]).to be_a(Integer)
      end

      it 'accepts actual Integer' do
        result = tool.validate_and_coerce_params(integer_param: 456)
        expect(result[:integer_param]).to eq(456)
      end

      it 'raises error for non-integer string' do
        expect {
          tool.validate_and_coerce_params(integer_param: 'not-a-number')
        }.to raise_error(ADK::ToolArgumentError, /expected Integer/)
      end
    end

    context 'Float coercion' do
      it 'coerces string float to Float' do
        result = tool.validate_and_coerce_params(float_param: '123.45')
        expect(result[:float_param]).to eq(123.45)
        expect(result[:float_param]).to be_a(Float)
      end

      it 'coerces integer to Float' do
        result = tool.validate_and_coerce_params(float_param: 123)
        expect(result[:float_param]).to eq(123.0)
        expect(result[:float_param]).to be_a(Float)
      end

      it 'raises error for non-numeric string' do
        expect {
          tool.validate_and_coerce_params(float_param: 'abc')
        }.to raise_error(ADK::ToolArgumentError, %r{expected Numeric/Float})
      end
    end

    context 'Boolean coercion' do
      it 'accepts true/false' do
        expect(tool.validate_and_coerce_params(boolean_param: true)[:boolean_param]).to be(true)
        expect(tool.validate_and_coerce_params(boolean_param: false)[:boolean_param]).to be(false)
      end

      it 'coerces "true", "t", "yes", "1" to true' do
        %w[true t yes 1 TRUE T YES].each do |val|
          expect(tool.validate_and_coerce_params(boolean_param: val)[:boolean_param]).to be(true)
        end
      end

      it 'coerces "false", "f", "no", "0" to false' do
        %w[false f no 0 FALSE F NO].each do |val|
          expect(tool.validate_and_coerce_params(boolean_param: val)[:boolean_param]).to be(false)
        end
      end

      it 'raises error for invalid boolean string' do
        expect {
          tool.validate_and_coerce_params(boolean_param: 'maybe')
        }.to raise_error(ADK::ToolArgumentError, /expected Boolean/)
      end
    end

    context 'Array coercion' do
      it 'accepts Array' do
        arr = [1, 2, 3]
        expect(tool.validate_and_coerce_params(array_param: arr)[:array_param]).to eq(arr)
      end

      it 'parses JSON array string' do
        json = '[1, "two", 3.0]'
        expect(tool.validate_and_coerce_params(array_param: json)[:array_param]).to eq([1, 'two', 3.0])
      end

      it 'raises error for invalid JSON' do
        expect {
          tool.validate_and_coerce_params(array_param: 'not json')
        }.to raise_error(ADK::ToolArgumentError, /expected Array/)
      end

      it 'raises error if JSON is not an Array' do
        expect {
          tool.validate_and_coerce_params(array_param: '{"key": "value"}')
        }.to raise_error(ADK::ToolArgumentError, /expected Array/)
      end
    end

    context 'Hash coercion' do
      it 'accepts Hash' do
        h = { 'a' => 1 }
        expect(tool.validate_and_coerce_params(hash_param: h)[:hash_param]).to eq(h)
      end

      it 'parses JSON hash string' do
        json = '{"key": "value"}'
        expect(tool.validate_and_coerce_params(hash_param: json)[:hash_param]).to eq({ 'key' => 'value' })
      end

      it 'raises error if JSON is not a Hash' do
        expect {
          tool.validate_and_coerce_params(hash_param: '[1, 2]')
        }.to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end
    end

    context 'String coercion' do
      it 'converts value to string' do
        expect(tool.validate_and_coerce_params(string_param: 123)[:string_param]).to eq('123')
      end
    end

    context 'Unknown type' do
      it 'returns value as is' do
        val = Object.new
        expect(tool.validate_and_coerce_params(any_param: val)[:any_param]).to be(val)
      end
    end

    context 'Nil handling' do
      it 'preserves nil values' do
        # Even if type is integer, if it's not required (default), nil is valid?
        # The code returns value if nil before coercion.
        # But if it's required, validation would have failed before coercion.
        # Since these are optional in my tool definition:
        expect(tool.validate_and_coerce_params(integer_param: nil)[:integer_param]).to be_nil
      end
    end

    context 'Extra parameters' do
      it 'preserves extra parameters not defined in metadata' do
        # Based on code reading: `coerced_params = normalized_params.dup` and loop over `current_parameters`.
        # So extra params are kept untouched.
        result = tool.validate_and_coerce_params(extra_param: 'something')
        expect(result[:extra_param]).to eq('something')
      end
    end
  end
end
