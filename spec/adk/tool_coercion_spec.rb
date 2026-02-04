# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool do
  let(:tool) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :test
      tool_description 'test'
      parameter :b, type: :boolean
      parameter :i, type: :integer
      parameter :f, type: :float
      parameter :a, type: :array
      parameter :h, type: :hash
      def perform_execution(*); end
    end.new
  end

  describe '#validate_and_coerce_params' do
    it 'coerces boolean strings' do
      %w[true t yes 1].each { |v| expect(tool.validate_and_coerce_params(b: v)[:b]).to be true }
      %w[false f no 0].each { |v| expect(tool.validate_and_coerce_params(b: v)[:b]).to be false }
      expect { tool.validate_and_coerce_params(b: 'x') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'coerces arrays and hashes from JSON strings' do
      res = tool.validate_and_coerce_params(a: '[1,2]', h: '{"k":"v"}')
      expect(res).to include(a: [1, 2], h: { 'k' => 'v' })
      expect { tool.validate_and_coerce_params(a: '{}') }.to raise_error(ADK::ToolArgumentError)
      expect { tool.validate_and_coerce_params(h: '[]') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'coerces numeric types' do
      expect(tool.validate_and_coerce_params(i: '123', f: '1.5')[:i]).to eq(123)
      expect { tool.validate_and_coerce_params(i: '1.5') }.to raise_error(ADK::ToolArgumentError)
      expect { tool.validate_and_coerce_params(i: 'abc') }.to raise_error(ADK::ToolArgumentError)
    end

    it 'accepts ruby objects directly' do
      expect(tool.validate_and_coerce_params(a: [1], h: { a: 1 })).to include(a: [1], h: { a: 1 })
    end
  end
end
