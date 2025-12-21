# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool do
  let(:tool_class) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :coercion_test
      tool_description 'Test Tool'
      parameter :req, type: :string, required: true
      parameter :int, type: :integer
      parameter :bool, type: :boolean
      parameter :arr, type: :array
      parameter :hsh, type: :hash
      def perform_execution(params, _); { status: :success, result: params }; end
    end
  end
  subject(:tool) { tool_class.new }

  describe '#validate_and_coerce_params' do
    it 'coerces strings to correct types' do
      res = tool.validate_and_coerce_params({ req: 's', int: '42', bool: 'yes', arr: '[1]', hsh: '{"a":1}' })
      expect(res).to include(int: 42, bool: true, arr: [1], hsh: { 'a' => 1 })
    end

    it 'preserves already correct types' do
      res = tool.validate_and_coerce_params({ req: 's', int: 42, bool: true, arr: [1], hsh: { a: 1 } })
      expect(res).to include(int: 42, bool: true, arr: [1], hsh: { a: 1 })
    end

    it 'handles boolean string variations' do
      %w[true t yes 1].each { |v| expect(tool.validate_and_coerce_params({ req: 's', bool: v })[:bool]).to be true }
      %w[false f no 0].each { |v| expect(tool.validate_and_coerce_params({ req: 's', bool: v })[:bool]).to be false }
    end

    it 'raises errors for invalid inputs' do
      expect { tool.validate_and_coerce_params({ req: 's', int: 'x' }) }.to raise_error(ADK::ToolArgumentError)
      expect { tool.validate_and_coerce_params({ req: 's', bool: 'x' }) }.to raise_error(ADK::ToolArgumentError)
      expect { tool.validate_and_coerce_params({ req: 's', arr: '{' }) }.to raise_error(ADK::ToolArgumentError)
      expect { tool.validate_and_coerce_params({ req: 's', hsh: '[' }) }.to raise_error(ADK::ToolArgumentError)
      expect { tool.validate_and_coerce_params({}) }.to raise_error(ADK::ToolArgumentError, /Missing required parameters/)
    end
  end
end
