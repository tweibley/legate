# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool, 'parameter coercion' do
  let(:tool_class) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :coercion_test_tool
      tool_description 'A tool for testing parameter coercion'

      parameter :int_param, type: :integer
      parameter :float_param, type: :float
      parameter :bool_param, type: :boolean
      parameter :string_param, type: :string
      parameter :array_param, type: :array
      parameter :hash_param, type: :hash
      parameter :req_param, type: :string, required: true

      def perform_execution(params, _context)
        { status: :success, result: params }
      end
    end
  end

  let(:tool) { tool_class.new }

  describe '#validate_and_coerce_params' do
    context 'with integer parameters' do
      it 'accepts integers' do
        params = { req_param: 'x', int_param: 123 }
        expect(tool.validate_and_coerce_params(params)).to include(int_param: 123)
      end

      it 'coerces valid integer strings' do
        params = { req_param: 'x', int_param: '456' }
        expect(tool.validate_and_coerce_params(params)).to include(int_param: 456)
      end

      it 'truncates floats to integers' do
        params = { req_param: 'x', int_param: 12.9 }
        expect(tool.validate_and_coerce_params(params)).to include(int_param: 12)
      end

      it 'raises error for non-integer strings' do
        params = { req_param: 'x', int_param: 'abc' }
        expect { tool.validate_and_coerce_params(params) }
          .to raise_error(ADK::ToolArgumentError, /expected Integer/)
      end
    end

    context 'with float parameters' do
      it 'accepts floats' do
        params = { req_param: 'x', float_param: 3.14 }
        expect(tool.validate_and_coerce_params(params)).to include(float_param: 3.14)
      end

      it 'coerces valid float strings' do
        params = { req_param: 'x', float_param: '3.14' }
        expect(tool.validate_and_coerce_params(params)).to include(float_param: 3.14)
      end

      it 'coerces integers to floats' do
        params = { req_param: 'x', float_param: 42 }
        expect(tool.validate_and_coerce_params(params)).to include(float_param: 42.0)
      end

      it 'raises error for invalid strings' do
        params = { req_param: 'x', float_param: 'not a number' }
        expect { tool.validate_and_coerce_params(params) }
          .to raise_error(ADK::ToolArgumentError, %r{expected Numeric/Float})
      end
    end

    context 'with boolean parameters' do
      it 'accepts true/false' do
        expect(tool.validate_and_coerce_params(req_param: 'x', bool_param: true)).to include(bool_param: true)
        expect(tool.validate_and_coerce_params(req_param: 'x', bool_param: false)).to include(bool_param: false)
      end

      it 'coerces truthy strings (case-insensitive)' do
        %w[true t yes 1 TRUE Yes].each do |val|
          params = { req_param: 'x', bool_param: val }
          expect(tool.validate_and_coerce_params(params)).to include(bool_param: true)
        end
      end

      it 'coerces falsy strings (case-insensitive)' do
        %w[false f no 0 FALSE No].each do |val|
          params = { req_param: 'x', bool_param: val }
          expect(tool.validate_and_coerce_params(params)).to include(bool_param: false)
        end
      end

      it 'raises error for invalid boolean strings' do
        params = { req_param: 'x', bool_param: 'maybe' }
        expect { tool.validate_and_coerce_params(params) }
          .to raise_error(ADK::ToolArgumentError, /expected Boolean/)
      end
    end

    context 'with array parameters' do
      it 'accepts arrays' do
        params = { req_param: 'x', array_param: [1, 2] }
        expect(tool.validate_and_coerce_params(params)).to include(array_param: [1, 2])
      end

      it 'parses valid JSON array strings' do
        params = { req_param: 'x', array_param: '[1, 2, "three"]' }
        expect(tool.validate_and_coerce_params(params)).to include(array_param: [1, 2, 'three'])
      end

      it 'raises error for invalid JSON' do
        params = { req_param: 'x', array_param: 'not json' }
        expect { tool.validate_and_coerce_params(params) }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end

      it 'raises error for valid JSON that is not an array' do
        params = { req_param: 'x', array_param: '{"a": 1}' }
        expect { tool.validate_and_coerce_params(params) }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end
    end

    context 'with hash parameters' do
      it 'accepts hashes' do
        params = { req_param: 'x', hash_param: { a: 1 } }
        expect(tool.validate_and_coerce_params(params)).to include(hash_param: { a: 1 })
      end

      it 'parses valid JSON hash strings' do
        params = { req_param: 'x', hash_param: '{"a": 1, "b": 2}' }
        result = tool.validate_and_coerce_params(params)
        expect(result[:hash_param]).to eq({ 'a' => 1, 'b' => 2 })
      end

      it 'raises error for invalid JSON' do
        params = { req_param: 'x', hash_param: '{invalid' }
        expect { tool.validate_and_coerce_params(params) }
          .to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end

      it 'raises error for valid JSON that is not a hash' do
        params = { req_param: 'x', hash_param: '[1, 2]' }
        expect { tool.validate_and_coerce_params(params) }
          .to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end
    end

    context 'with general behavior' do
      it 'symbolizes keys' do
        params = { 'req_param' => 'val', 'int_param' => 1 }
        expect(tool.validate_and_coerce_params(params)).to include(req_param: 'val', int_param: 1)
      end

      it 'raises error for missing required parameter' do
        expect { tool.validate_and_coerce_params(int_param: 1) }
          .to raise_error(ADK::ToolArgumentError, /Missing required parameters.*req_param/)
      end

      it 'preserves extra parameters not in definition' do
        params = { req_param: 'x', extra_stuff: 'preserved' }
        expect(tool.validate_and_coerce_params(params)).to include(extra_stuff: 'preserved')
      end

      it 'ignores nil values for optional parameters' do
        params = { req_param: 'x', int_param: nil }
        expect(tool.validate_and_coerce_params(params)).to include(int_param: nil)
      end
    end
  end
end
