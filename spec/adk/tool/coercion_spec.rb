# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool, 'Parameter Coercion' do
  let(:tool) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :coercion_tool
      tool_description 'Test Tool'
      parameter :bool_param, type: :boolean, required: false
      parameter :array_param, type: :array, required: false

      def perform_execution(params, _context)
        { status: :success, result: params }
      end
    end.new
  end

  def execute_with(params)
    tool.execute(params, instance_double(ADK::ToolContext, to_h: {}))[:result]
  end

  describe 'Boolean Coercion' do
    it 'handles string variants' do
      %w[true t yes 1].each { |v| expect(execute_with(bool_param: v)[:bool_param]).to be(true) }
      %w[false f no 0].each { |v| expect(execute_with(bool_param: v)[:bool_param]).to be(false) }
    end

    it 'raises on invalid strings' do
      expect { execute_with(bool_param: 'maybe') }.to raise_error(ADK::ToolArgumentError)
    end
  end

  describe 'JSON Coercion' do
    it 'parses valid JSON arrays' do
      expect(execute_with(array_param: '[1, "two"]')[:array_param]).to eq([1, 'two'])
    end

    it 'raises on malformed JSON' do
      expect { execute_with(array_param: '[1,') }.to raise_error(ADK::ToolArgumentError)
    end
  end
end
