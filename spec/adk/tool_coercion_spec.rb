# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool, 'parameter coercion' do
  let(:tool_class) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :coercion_test
      tool_description 'Test tool for parameter coercion'

      parameter :bool_param, type: :boolean
      parameter :int_param, type: :integer
      parameter :float_param, type: :float
      parameter :array_param, type: :array
      parameter :hash_param, type: :hash

      def perform_execution(params, _); { result: params }; end
    end
  end
  let(:tool) { tool_class.new }

  describe 'boolean coercion' do
    it 'coerces truthy strings' do
      %w[true True TRUE t yes 1].each do |val|
        expect(tool.execute(bool_param: val)[:result][:bool_param]).to be(true), "Failed for #{val}"
      end
    end

    it 'coerces falsy strings' do
      %w[false False FALSE f no 0].each do |val|
        expect(tool.execute(bool_param: val)[:result][:bool_param]).to be(false), "Failed for #{val}"
      end
    end

    it 'raises error for invalid values' do
      expect { tool.execute(bool_param: 'maybe') }.to raise_error(ADK::ToolArgumentError, /expected Boolean/)
      expect { tool.execute(bool_param: 123) }.to raise_error(ADK::ToolArgumentError, /expected Boolean/)
    end
  end

  describe 'JSON parsing coercion' do
    it 'coerces valid JSON strings to array/hash' do
      expect(tool.execute(array_param: '[1, 2]')[:result][:array_param]).to eq([1, 2])
      expect(tool.execute(hash_param: '{"a": 1}')[:result][:hash_param]).to eq({ 'a' => 1 })
    end

    it 'raises error for invalid JSON or type mismatch' do
      expect { tool.execute(array_param: 'not_json') }.to raise_error(ADK::ToolArgumentError, /expected Array/)
      expect { tool.execute(array_param: '{"not": "array"}') }.to raise_error(ADK::ToolArgumentError, /expected Array/)
      expect { tool.execute(hash_param: '[1, 2]') }.to raise_error(ADK::ToolArgumentError, /expected Hash/)
    end
  end

  describe 'numeric coercion' do
    it 'coerces numeric strings' do
      expect(tool.execute(int_param: '42')[:result][:int_param]).to eq(42)
      expect(tool.execute(float_param: '3.14')[:result][:float_param]).to eq(3.14)
    end

    it 'raises error for non-numeric strings' do
      expect { tool.execute(int_param: 'abc') }.to raise_error(ADK::ToolArgumentError, /expected Integer/)
      expect { tool.execute(float_param: 'abc') }.to raise_error(ADK::ToolArgumentError, /expected Numeric\/Float/)
    end
  end
end
