# File: spec/legate/tool_code_generator_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/tool_code_generator'

RSpec.describe Legate::ToolCodeGenerator do
  # Ensure tools are registered before each test (spec_helper resets after each)
  before(:each) do
    Legate::GlobalToolManager.register_tool(Legate::Tools::Echo)
    Legate::GlobalToolManager.register_tool(Legate::Tools::Calculator)
  end

  describe '.generate' do
    context 'with a registered tool' do
      it 'generates valid Ruby code for the echo tool' do
        code = described_class.generate(:echo)

        expect(code).to include("require 'legate/tool'")
        expect(code).to include('class Echo < Tool')
        expect(code).to include('tool_description')
        expect(code).to include('parameter :message')
        expect(code).to include('def perform_execution(params, context)')
        expect(code).to include('Legate::GlobalToolManager.register_tool')
      end

      it 'generates syntactically valid Ruby for echo tool' do
        code = described_class.generate(:echo)
        expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
      end

      it 'generates valid Ruby code for the calculator tool' do
        code = described_class.generate(:calculator)

        expect(code).to include('class Calculator < Tool')
        expect(code).to include('parameter :operand1')
        expect(code).to include('parameter :operand2')
        expect(code).to include('parameter :operation')
      end

      it 'generates syntactically valid Ruby for calculator tool' do
        code = described_class.generate(:calculator)
        expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
      end
    end

    context 'with unregistered tool' do
      it 'returns nil for non-existent tool' do
        code = described_class.generate(:nonexistent_tool_xyz)
        expect(code).to be_nil
      end
    end

    context 'generated code structure' do
      let(:code) { described_class.generate(:echo) }

      it 'includes frozen_string_literal comment' do
        expect(code).to include('# frozen_string_literal: true')
      end

      it 'includes generation timestamp comment' do
        expect(code).to include('# Generated from Legate Web UI on')
      end

      it 'wraps class in Legate::Tools module' do
        expect(code).to include('module Legate')
        expect(code).to include('module Tools')
      end

      it 'includes TODO comment for implementation' do
        expect(code).to include('# TODO: Implement your tool logic here')
      end

      it 'includes context method documentation' do
        expect(code).to include('context.state_get(:key)')
        expect(code).to include('context.state_set(:key, value)')
      end

      it 'includes parameter access examples' do
        expect(code).to include('# message = params[:message]')
      end
    end

    context 'with multiple parameter types' do
      it 'handles different parameter types correctly' do
        code = described_class.generate(:calculator)

        # Calculator has numeric and string parameters
        expect(code).to include('type: :numeric')
        expect(code).to include('type: :string')
      end
    end
  end
end
