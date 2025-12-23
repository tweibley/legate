# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool do
  class CoercionTestTool < ADK::Tool
    self.explicit_tool_name = :coercion_test
    tool_description 'Tool for testing coercion'

    parameter :str, type: :string
    parameter :int, type: :integer
    parameter :flt, type: :float
    parameter :bool, type: :boolean
    parameter :arr, type: :array
    parameter :hsh, type: :hash
    parameter :any, type: :any

    def perform_execution(params, context)
      { status: :success, result: params }
    end
  end

  let(:tool) { CoercionTestTool.new }

  describe '#validate_and_coerce_params' do
    it 'coerces integers' do
      expect(tool.validate_and_coerce_params(int: '123')[:int]).to eq(123)
      expect(tool.validate_and_coerce_params(int: 123)[:int]).to eq(123)
      expect { tool.validate_and_coerce_params(int: 'abc') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'coerces floats' do
      expect(tool.validate_and_coerce_params(flt: '12.34')[:flt]).to eq(12.34)
      expect(tool.validate_and_coerce_params(flt: 12.34)[:flt]).to eq(12.34)
      expect { tool.validate_and_coerce_params(flt: 'abc') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'coerces booleans' do
      expect(tool.validate_and_coerce_params(bool: true)[:bool]).to be true
      expect(tool.validate_and_coerce_params(bool: 'true')[:bool]).to be true
      expect(tool.validate_and_coerce_params(bool: 'yes')[:bool]).to be true
      expect(tool.validate_and_coerce_params(bool: '1')[:bool]).to be true

      expect(tool.validate_and_coerce_params(bool: false)[:bool]).to be false
      expect(tool.validate_and_coerce_params(bool: 'false')[:bool]).to be false
      expect(tool.validate_and_coerce_params(bool: 'no')[:bool]).to be false
      expect(tool.validate_and_coerce_params(bool: '0')[:bool]).to be false

      expect { tool.validate_and_coerce_params(bool: 'invalid') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'coerces arrays' do
      expect(tool.validate_and_coerce_params(arr: [1, 2])[:arr]).to eq([1, 2])
      expect(tool.validate_and_coerce_params(arr: '[1, 2]')[:arr]).to eq([1, 2])
      expect { tool.validate_and_coerce_params(arr: 'not an array') }.to raise_error(ADK::ToolArgumentError)
      expect { tool.validate_and_coerce_params(arr: '{"a":1}') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'coerces hashes' do
      expect(tool.validate_and_coerce_params(hsh: { a: 1 })[:hsh]).to eq({ a: 1 })
      expect(tool.validate_and_coerce_params(hsh: '{"a": 1}')[:hsh]).to eq({ "a" => 1 })
      expect { tool.validate_and_coerce_params(hsh: 'not a hash') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'handles nil values' do
      expect(tool.validate_and_coerce_params(str: nil)[:str]).to be_nil
    end

    it 'handles unknown types' do
      val = Object.new
      expect(tool.validate_and_coerce_params(any: val)[:any]).to eq(val)
    end
  end
end
