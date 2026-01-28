# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool'

RSpec.describe ADK::Tool do
  # Define a tool specifically for testing coercion
  let(:tool_class) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :coercion_test_tool
      tool_description 'Tool for testing parameter coercion'

      parameter :int_param, type: :integer, required: false
      parameter :float_param, type: :float, required: false
      parameter :bool_param, type: :boolean, required: false
      parameter :array_param, type: :array, required: false
      parameter :hash_param, type: :hash, required: false

      def perform_execution(params, _context)
        { status: :success, result: params }
      end
    end
  end

  let(:tool) { tool_class.new }
  let(:context) { instance_double(ADK::ToolContext) }

  before do
    allow(context).to receive(:to_h).and_return({ session_id: 'test' })
  end

  describe 'Parameter Coercion' do
    describe 'Integer coercion' do
      it 'accepts integers' do
        result = tool.execute({ int_param: 123 }, context)
        expect(result[:result][:int_param]).to eq(123)
      end

      it 'coerces string integers' do
        result = tool.execute({ int_param: '456' }, context)
        expect(result[:result][:int_param]).to eq(456)
      end

      it 'truncates float values' do
        # This documents current behavior: Integer(12.9) -> 12
        result = tool.execute({ int_param: 12.9 }, context)
        expect(result[:result][:int_param]).to eq(12)
      end

      it 'raises error for float-like strings' do
        # Integer("12.5") raises ArgumentError
        expect { tool.execute({ int_param: '12.5' }, context) }
          .to raise_error(ADK::ToolArgumentError, /expected Integer/)
      end

      it 'raises error for non-numeric strings' do
        expect { tool.execute({ int_param: 'abc' }, context) }
          .to raise_error(ADK::ToolArgumentError, /expected Integer/)
      end
    end

    describe 'Float coercion' do
      it 'accepts floats' do
        result = tool.execute({ float_param: 12.34 }, context)
        expect(result[:result][:float_param]).to eq(12.34)
      end

      it 'coerces integers to float' do
        result = tool.execute({ float_param: 10 }, context)
        expect(result[:result][:float_param]).to eq(10.0)
      end

      it 'coerces string floats' do
        result = tool.execute({ float_param: '56.78' }, context)
        expect(result[:result][:float_param]).to eq(56.78)
      end

      it 'raises error for invalid strings' do
        expect { tool.execute({ float_param: 'not-a-float' }, context) }
          .to raise_error(ADK::ToolArgumentError, %r{expected Numeric/Float})
      end
    end

    describe 'Boolean coercion' do
      it 'accepts true/false' do
        expect(tool.execute({ bool_param: true }, context)[:result][:bool_param]).to be true
        expect(tool.execute({ bool_param: false }, context)[:result][:bool_param]).to be false
      end

      it 'coerces truthy strings' do
        %w[true t yes 1].each do |val|
          expect(tool.execute({ bool_param: val }, context)[:result][:bool_param]).to be true
        end
        %w[TRUE Yes].each do |val|
          expect(tool.execute({ bool_param: val }, context)[:result][:bool_param]).to be true
        end
      end

      it 'coerces falsy strings' do
        %w[false f no 0].each do |val|
          expect(tool.execute({ bool_param: val }, context)[:result][:bool_param]).to be false
        end
        %w[FALSE No].each do |val|
          expect(tool.execute({ bool_param: val }, context)[:result][:bool_param]).to be false
        end
      end

      it 'raises error for invalid boolean strings' do
        expect { tool.execute({ bool_param: 'maybe' }, context) }
          .to raise_error(ADK::ToolArgumentError, /expected Boolean/)
      end
    end

    describe 'Array coercion' do
      it 'accepts arrays' do
        result = tool.execute({ array_param: [1, 2] }, context)
        expect(result[:result][:array_param]).to eq([1, 2])
      end

      it 'parses valid JSON array strings' do
        result = tool.execute({ array_param: '[1, "two"]' }, context)
        expect(result[:result][:array_param]).to eq([1, 'two'])
      end

      it 'raises error if JSON parses but is not an array' do
        expect { tool.execute({ array_param: '{"key": "value"}' }, context) }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end

      it 'raises error for invalid JSON' do
        expect { tool.execute({ array_param: '[1, 2' }, context) }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end
    end

    describe 'Hash coercion' do
      it 'accepts hashes' do
        result = tool.execute({ hash_param: { a: 1 } }, context)
        expect(result[:result][:hash_param]).to eq({ a: 1 })
      end

      it 'parses valid JSON hash strings' do
        result = tool.execute({ hash_param: '{"b": 2}' }, context)
        expect(result[:result][:hash_param]).to eq({ 'b' => 2 })
      end

      it 'raises error if JSON parses but is not a hash' do
        expect { tool.execute({ hash_param: '[1, 2]' }, context) }
          .to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end

      it 'raises error for invalid JSON' do
        expect { tool.execute({ hash_param: '{ bad json }' }, context) }
          .to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end
    end
  end
end
