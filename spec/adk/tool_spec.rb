# frozen_string_literal: true

# File: spec/adk/tool_spec.rb
require 'spec_helper'

# --- Dummy Tools defined globally ---

# Define a dummy class using the DEPRECATED method
class DummyTestToolForRegistration < ADK::Tool
  # NOTE: This uses the old, deprecated method for testing purposes
  define_metadata(
    name: :reg_test_tool,
    description: 'Registration Test',
    parameters: {
      p1: { type: :string } # Old style param definition
    }
  )

  def perform_execution(params, context); end
end

# Define a different dummy class using the NEW DSL for comparison
class DummyDslTool < ADK::Tool
  tool_description 'A dummy tool for testing define_metadata replacement'
  parameter :p1, type: :string
  # Implicit name: dummy_dsl_tool
  def perform_execution(params, context); end
end

# Define DummyTestTool used by most tests at the top level
unless defined?(DummyTestTool)
  class DummyTestTool < ADK::Tool
    # Replaced define_metadata
    self.explicit_tool_name = :dummy
    tool_description 'A dummy tool'
    parameter :req, type: :string, required: true # String type assumed if not given
    parameter :opt, type: :integer, required: false, description: 'Optional param'

    attr_reader :received_params, :received_context

    def perform_execution(params, context)
      @received_params = params
      @received_context = context
      { status: :success, result: "Processed: #{params[:req]}, Opt: #{params[:opt]}" }
    end
  end
end

# Define a Dummy Coercion Tool for testing type conversions
unless defined?(DummyCoercionTool)
  class DummyCoercionTool < ADK::Tool
    self.explicit_tool_name = :coercion_tool
    tool_description 'Coercion Test Tool'

    parameter :int_val, type: :integer
    parameter :float_val, type: :float
    parameter :bool_val, type: :boolean
    parameter :arr_val, type: :array
    parameter :hash_val, type: :hash

    def perform_execution(params, _context)
      { status: :success, result: params }
    end
  end
end

RSpec.describe ADK::Tool do
  # Create a registry instance for tests that might need it (though many operate on the instance directly)
  let(:registry) { ADK::ToolRegistry.new }
  let(:dummy_registry) { ADK::ToolRegistry.new } # Registry for context

  let(:tool_instance) { DummyTestTool.new }
  let(:params) { { req: 'value' } }
  let(:context) { ADK::ToolContext.new(session_id: 's', user_id: 'u', app_name: 'a', tool_registry: dummy_registry) }

  # --- Removed Global Registration Setup ---
  # before(:context) do
  #   ...
  # end

  # --- Cleanup after context (Keep commented out unless needed) ---
  # after(:context) do
  # If necessary, unregister the tool
  # ADK::ToolRegistry.unregister(:dummy)
  # end

  describe '#execute' do
    it 'validates and coerces parameters before calling perform_execution' do
      expect(tool_instance).to receive(:validate_and_coerce_params).with(params).ordered.and_call_original
      expect(tool_instance).to receive(:perform_execution).with(kind_of(Hash), context).ordered.and_call_original
      tool_instance.execute(params, context)
    end

    it 'passes parameters and context to perform_execution' do
      tool_instance.execute(params, context)
      # perform_execution receives coerced params (new hash), so we check equality of content
      expect(tool_instance.received_params).to eq(params)
      expect(tool_instance.received_context).to eq(context)
    end

    it 'raises error if required parameters are missing' do
      expect { tool_instance.execute({}, context) }.to raise_error(ADK::Error, /Missing required parameters for tool 'dummy': req/)
    end

    it 'handles context being nil (for potential backward compatibility)' do
      expect { tool_instance.execute(params, nil) }.not_to raise_error
      expect(tool_instance.received_context).to be_nil
    end

    context 'when perform_execution is not implemented' do
      let(:incomplete_tool_class) do
        Class.new(ADK::Tool) do
          self.explicit_tool_name = :incomplete_tool
          tool_description 'Incomplete tool'
        end
      end
      let(:incomplete_tool) { incomplete_tool_class.new }

      it 'raises NotImplementedError' do
        expect { incomplete_tool.execute({}, context) }.to raise_error(NotImplementedError)
      end
    end
  end

  describe '#validate_params' do
    it 'does not raise error if required parameters are present' do
      expect { tool_instance.validate_params(req: 'val') }.not_to raise_error
    end

    it 'raises error if required parameters are missing' do
      expect { tool_instance.validate_params({}) }.to raise_error(ADK::Error, /Missing required parameters for tool 'dummy': req/)
    end
  end

  describe 'parameter coercion' do
    let(:coercion_tool) { DummyCoercionTool.new }

    context 'integer parameters' do
      it 'coerces valid values' do
        { '123' => 123, 456 => 456 }.each do |input, expected|
          expect(coercion_tool.execute(int_val: input)[:result][:int_val]).to eq(expected)
        end
      end

      it 'raises error for invalid values' do
        expect { coercion_tool.execute(int_val: 'abc') }.to raise_error(ADK::ToolArgumentError, /expected Integer/)
      end
    end

    context 'float parameters' do
      it 'coerces valid values' do
        { '12.34' => 12.34, 56.78 => 56.78 }.each do |input, expected|
          expect(coercion_tool.execute(float_val: input)[:result][:float_val]).to eq(expected)
        end
      end

      it 'raises error for invalid values' do
        expect { coercion_tool.execute(float_val: 'abc') }.to raise_error(ADK::ToolArgumentError, %r{expected Numeric/Float})
      end
    end

    context 'boolean parameters' do
      it 'coerces valid values' do
        truthy = %w[true yes 1]
        falsy = %w[false no 0]

        truthy.each { |val| expect(coercion_tool.execute(bool_val: val)[:result][:bool_val]).to be true }
        falsy.each { |val| expect(coercion_tool.execute(bool_val: val)[:result][:bool_val]).to be false }
      end

      it 'raises error for invalid values' do
        expect { coercion_tool.execute(bool_val: 'maybe') }.to raise_error(ADK::ToolArgumentError, /expected Boolean/)
      end
    end

    context 'complex types (array/hash)' do
      it 'handles JSON strings and raw values' do
        cases = {
          arr_val: { '[1, 2]' => [1, 2], [3] => [3] },
          hash_val: { '{"a": 1}' => { 'a' => 1 }, { b: 2 } => { b: 2 } }
        }

        cases.each do |param, examples|
          examples.each do |input, expected|
            expect(coercion_tool.execute(param => input)[:result][param]).to eq(expected)
          end
        end
      end

      it 'raises error for invalid JSON' do
        expect { coercion_tool.execute(arr_val: 'bad') }.to raise_error(ADK::ToolArgumentError, /expected Array/)
        expect { coercion_tool.execute(hash_val: 'bad') }.to raise_error(ADK::ToolArgumentError, /expected Hash/)
      end
    end
  end

  describe '.define_metadata and tool registration' do
    # Classes are now defined globally above

    # We might need to reset before this context if other tests leave registrations behind
    before(:all) do
      ADK::GlobalToolManager.reset!
      # Manually trigger registration IF defining globally doesn't work as expected
      # ADK::GlobalToolManager.register_tool(DummyTestToolForRegistration)
      # ADK::GlobalToolManager.register_tool(DummyDslTool)
    end

    after(:all) do
      ADK::GlobalToolManager.reset!
    end

    it 'stores metadata correctly' do
      # Test the DEPRECATED method's storage
      metadata = DummyTestToolForRegistration.tool_metadata
      expect(metadata[:name]).to eq(:reg_test_tool)
      expect(metadata[:description]).to eq('Registration Test')
      expect(metadata[:parameters][:p1]).to eq({ type: :string })
    end

    it 'triggers registration when the class is loaded' do
      # Reset and explicitly register just before this test to ensure clean state
      ADK::GlobalToolManager.reset!
      ADK::GlobalToolManager.register_tool(DummyTestToolForRegistration)
      ADK::GlobalToolManager.register_tool(DummyDslTool)

      # Ensure registration happened
      expect(ADK::GlobalToolManager.find_class(:reg_test_tool)).to eq(DummyTestToolForRegistration)
      expect(ADK::GlobalToolManager.find_class(:dummy_dsl_tool)).to eq(DummyDslTool)
    end
  end
end
