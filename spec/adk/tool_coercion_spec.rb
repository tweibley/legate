# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool do
  # Create a concrete subclass for testing since ADK::Tool is abstract-ish
  let(:tool_class) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :coercion_test_tool
      tool_description 'Tool for testing coercion'

      # Define parameters of various types
      parameter :str_param, type: :string
      parameter :int_param, type: :integer
      parameter :float_param, type: :float
      parameter :bool_param, type: :boolean
      parameter :arr_param, type: :array
      parameter :hash_param, type: :hash

      def perform_execution(params, context); end
    end
  end

  subject(:tool) { tool_class.new }

  describe '#validate_and_coerce_params' do
    context 'when coercing Strings' do
      it 'keeps strings as strings' do
        expect(tool.validate_and_coerce_params(str_param: 'foo')[:str_param]).to eq('foo')
      end

      it 'converts numbers to strings' do
        expect(tool.validate_and_coerce_params(str_param: 123)[:str_param]).to eq('123')
      end
    end

    context 'when coercing Integers' do
      it 'coerces valid integer strings' do
        expect(tool.validate_and_coerce_params(int_param: '123')[:int_param]).to eq(123)
      end

      it 'truncates floats to integers' do
        expect(tool.validate_and_coerce_params(int_param: 12.9)[:int_param]).to eq(12)
      end

      it 'raises error for invalid integer strings' do
        expect { tool.validate_and_coerce_params(int_param: 'abc') }
          .to raise_error(ADK::ToolArgumentError, /expected Integer/)
      end
    end

    context 'when coercing Floats' do
      it 'coerces valid float strings' do
        expect(tool.validate_and_coerce_params(float_param: '12.34')[:float_param]).to eq(12.34)
      end

      it 'coerces integers to floats' do
        expect(tool.validate_and_coerce_params(float_param: 10)[:float_param]).to eq(10.0)
      end

      it 'raises error for invalid float strings' do
        expect { tool.validate_and_coerce_params(float_param: 'not-a-number') }
          .to raise_error(ADK::ToolArgumentError, /expected Numeric\/Float/)
      end
    end

    context 'when coercing Booleans' do
      it 'coerces "true", "t", "yes", "1" to true (case insensitive)' do
        %w[true TRUE t yes 1].each do |val|
          expect(tool.validate_and_coerce_params(bool_param: val)[:bool_param]).to be(true)
        end
      end

      it 'coerces "false", "f", "no", "0" to false (case insensitive)' do
        %w[false FALSE f no 0].each do |val|
          expect(tool.validate_and_coerce_params(bool_param: val)[:bool_param]).to be(false)
        end
      end

      it 'raises error for invalid boolean strings' do
        expect { tool.validate_and_coerce_params(bool_param: 'maybe') }
          .to raise_error(ADK::ToolArgumentError, /expected Boolean/)
      end

      it 'raises error for other types' do
        expect { tool.validate_and_coerce_params(bool_param: 123) }
          .to raise_error(ADK::ToolArgumentError, /expected Boolean/)
      end
    end

    context 'when coercing Arrays' do
      it 'accepts ruby arrays' do
        expect(tool.validate_and_coerce_params(arr_param: [1, 2])[:arr_param]).to eq([1, 2])
      end

      it 'coerces JSON string to Array' do
        expect(tool.validate_and_coerce_params(arr_param: '[1, 2, 3]')[:arr_param]).to eq([1, 2, 3])
      end

      it 'raises error for non-array JSON' do
        expect { tool.validate_and_coerce_params(arr_param: '{"a":1}') }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end

      it 'raises error for malformed JSON' do
        expect { tool.validate_and_coerce_params(arr_param: '[1, 2') }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end

      it 'raises error for other types' do
        expect { tool.validate_and_coerce_params(arr_param: 123) }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end
    end

    context 'when coercing Hashes' do
      it 'accepts ruby hashes' do
        expect(tool.validate_and_coerce_params(hash_param: { a: 1 })[:hash_param]).to eq({ a: 1 })
      end

      it 'coerces JSON string to Hash' do
        expect(tool.validate_and_coerce_params(hash_param: '{"a": 1}')[:hash_param]).to eq({ 'a' => 1 })
      end

      it 'raises error for non-hash JSON' do
        expect { tool.validate_and_coerce_params(hash_param: '[1, 2]') }
          .to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end

      it 'raises error for malformed JSON' do
        expect { tool.validate_and_coerce_params(hash_param: '{a: 1}') } # invalid json
          .to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end

      it 'raises error for other types' do
        expect { tool.validate_and_coerce_params(hash_param: 123) }
          .to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end
    end

    context 'with nil values' do
      it 'preserves nil values (letting them be handled by app logic)' do
        # If parameter is not required, nil might be passed through
        # But here we pass keys, if we pass key with nil value:
        expect(tool.validate_and_coerce_params(str_param: nil)[:str_param]).to be_nil
      end
    end
  end
end
