# frozen_string_literal: true

require 'spec_helper'

# Define a dedicated tool for coercion testing
class CoercionTestTool < ADK::Tool
  self.explicit_tool_name = :coercion_test
  tool_description 'Test tool for parameter coercion'

  parameter :str_param, type: :string, required: false
  parameter :int_param, type: :integer, required: false
  parameter :float_param, type: :float, required: false
  parameter :bool_param, type: :boolean, required: false
  parameter :arr_param, type: :array, required: false
  parameter :hash_param, type: :hash, required: false

  def perform_execution(params, context); end
end

RSpec.describe ADK::Tool do
  let(:tool) { CoercionTestTool.new }
  let(:context) { nil }

  describe '#validate_and_coerce_params' do
    context 'String coercion' do
      it 'converts various types to string' do
        result = tool.validate_and_coerce_params(str_param: 123)
        expect(result[:str_param]).to eq('123')

        result = tool.validate_and_coerce_params(str_param: true)
        expect(result[:str_param]).to eq('true')
      end

      it 'keeps strings as strings' do
        result = tool.validate_and_coerce_params(str_param: 'hello')
        expect(result[:str_param]).to eq('hello')
      end
    end

    context 'Integer coercion' do
      it 'keeps integers as integers' do
        result = tool.validate_and_coerce_params(int_param: 42)
        expect(result[:int_param]).to eq(42)
      end

      it 'converts numeric strings to integers' do
        result = tool.validate_and_coerce_params(int_param: '42')
        expect(result[:int_param]).to eq(42)
      end

      it 'truncates floats' do
        result = tool.validate_and_coerce_params(int_param: 42.9)
        expect(result[:int_param]).to eq(42)
      end

      it 'raises error for invalid strings' do
        expect { tool.validate_and_coerce_params(int_param: 'not-a-number') }
          .to raise_error(ADK::ToolArgumentError, /expected Integer/)
      end
    end

    context 'Float coercion' do
      it 'keeps floats as floats' do
        result = tool.validate_and_coerce_params(float_param: 3.14)
        expect(result[:float_param]).to eq(3.14)
      end

      it 'converts integers to floats' do
        result = tool.validate_and_coerce_params(float_param: 42)
        expect(result[:float_param]).to eq(42.0)
      end

      it 'converts numeric strings to floats' do
        result = tool.validate_and_coerce_params(float_param: '3.14')
        expect(result[:float_param]).to eq(3.14)
      end

      it 'raises error for invalid strings' do
        expect { tool.validate_and_coerce_params(float_param: 'not-a-float') }
          .to raise_error(ADK::ToolArgumentError, %r{expected Numeric/Float})
      end
    end

    context 'Boolean coercion' do
      it 'keeps booleans as booleans' do
        expect(tool.validate_and_coerce_params(bool_param: true)[:bool_param]).to be(true)
        expect(tool.validate_and_coerce_params(bool_param: false)[:bool_param]).to be(false)
      end

      it 'converts "truthy" strings to true' do
        %w[true t yes 1].each do |val|
          expect(tool.validate_and_coerce_params(bool_param: val)[:bool_param]).to be(true)
        end
      end

      it 'converts "falsy" strings to false' do
        %w[false f no 0].each do |val|
          expect(tool.validate_and_coerce_params(bool_param: val)[:bool_param]).to be(false)
        end
      end

      it 'is case insensitive' do
        expect(tool.validate_and_coerce_params(bool_param: 'TRUE')[:bool_param]).to be(true)
        expect(tool.validate_and_coerce_params(bool_param: 'No')[:bool_param]).to be(false)
      end

      it 'raises error for invalid strings' do
        expect { tool.validate_and_coerce_params(bool_param: 'maybe') }
          .to raise_error(ADK::ToolArgumentError, /expected Boolean/)
      end

      it 'raises error for non-boolean/non-string types' do
        expect { tool.validate_and_coerce_params(bool_param: 123) }
          .to raise_error(ADK::ToolArgumentError, /expected Boolean/)
      end
    end

    context 'Array coercion' do
      it 'keeps arrays as arrays' do
        expect(tool.validate_and_coerce_params(arr_param: [1, 2])[:arr_param]).to eq([1, 2])
      end

      it 'parses JSON strings to arrays' do
        expect(tool.validate_and_coerce_params(arr_param: '[1, 2]')[:arr_param]).to eq([1, 2])
      end

      it 'raises error for invalid JSON' do
        expect { tool.validate_and_coerce_params(arr_param: '[1, 2') }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end

      it 'raises error if JSON is not an array' do
        expect { tool.validate_and_coerce_params(arr_param: '{"a": 1}') }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end

      it 'raises error for other types' do
        expect { tool.validate_and_coerce_params(arr_param: 123) }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end
    end

    context 'Hash coercion' do
      it 'keeps hashes as hashes' do
        expect(tool.validate_and_coerce_params(hash_param: { a: 1 })[:hash_param]).to eq({ a: 1 })
      end

      it 'parses JSON strings to hashes' do
        expect(tool.validate_and_coerce_params(hash_param: '{"a": 1}')[:hash_param]).to eq({ 'a' => 1 })
      end

      it 'raises error for invalid JSON' do
        expect { tool.validate_and_coerce_params(hash_param: '{a: 1}') }
          .to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end

      it 'raises error if JSON is not a hash' do
        expect { tool.validate_and_coerce_params(hash_param: '[1, 2]') }
          .to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end

      it 'raises error for other types' do
        expect { tool.validate_and_coerce_params(hash_param: 123) }
          .to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end
    end

    context 'Nil handling' do
      it 'returns nil for missing optional parameters' do
        expect(tool.validate_and_coerce_params({})[:str_param]).to be_nil
      end

      it 'returns nil for explicitly nil parameters' do
        expect(tool.validate_and_coerce_params(str_param: nil)[:str_param]).to be_nil
      end
    end
  end
end
