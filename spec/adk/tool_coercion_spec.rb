# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool do
  describe 'parameter coercion' do
    let(:tool) do
      Class.new(ADK::Tool) do
        self.explicit_tool_name = :coercion_test
        tool_description 'Coercion Test'
        parameter :str, type: :string
        parameter :int, type: :integer
        parameter :flt, type: :float
        parameter :bool, type: :boolean
        parameter :arr, type: :array
        parameter :hsh, type: :hash

        def perform_execution(params, _ctx)
          { status: :success, result: params }
        end
      end.new
    end

    def coerce(params)
      tool.validate_and_coerce_params(params)
    end

    it 'coerces integers correctly' do
      expect(coerce(int: '123')[:int]).to eq(123)
      expect(coerce(int: 456)[:int]).to eq(456)
      expect(coerce(int: 12.9)[:int]).to eq(12) # Truncates
      expect { coerce(int: '12.3') }.to raise_error(ADK::ToolArgumentError)
      expect { coerce(int: 'abc') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'coerces floats correctly' do
      expect(coerce(flt: '12.34')[:flt]).to eq(12.34)
      expect(coerce(flt: 10)[:flt]).to eq(10.0)
      expect { coerce(flt: 'abc') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'coerces booleans correctly' do
      %w[true t yes 1].each { |v| expect(coerce(bool: v)[:bool]).to be true }
      %w[false f no 0].each { |v| expect(coerce(bool: v)[:bool]).to be false }
      expect(coerce(bool: true)[:bool]).to be true
      expect { coerce(bool: 'maybe') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'coerces arrays correctly' do
      expect(coerce(arr: [1, 2])[:arr]).to eq([1, 2])
      expect(coerce(arr: '[1, 2]')[:arr]).to eq([1, 2])
      expect { coerce(arr: '{"a":1}') }.to raise_error(ADK::ToolArgumentError)
      expect { coerce(arr: 'invalid') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'coerces hashes correctly' do
      expect(coerce(hsh: { a: 1 })[:hsh]).to eq({ a: 1 })
      expect(coerce(hsh: '{"a": 1}')[:hsh]).to eq({ 'a' => 1 })
      expect { coerce(hsh: '[1]') }.to raise_error(ADK::ToolArgumentError)
      expect { coerce(hsh: 'invalid') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'enforces required parameters' do
      req_tool = Class.new(ADK::Tool) do
        self.explicit_tool_name = :req_test
        tool_description 'Required Param Test'
        parameter :req, type: :string, required: true
      end.new

      expect { req_tool.validate_and_coerce_params({}) }
        .to raise_error(ADK::ToolArgumentError, /Missing required parameters/)
    end
  end
end
