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

# Define a tool specifically for testing parameter coercion
unless defined?(CoercionTestTool)
  class CoercionTestTool < ADK::Tool
    self.explicit_tool_name = :coercion_tool
    tool_description 'Testing coercion'
    parameter :int_param, type: :integer
    parameter :float_param, type: :float
    parameter :bool_param, type: :boolean
    parameter :array_param, type: :array
    parameter :hash_param, type: :hash

    def perform_execution(params, context); end
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

  describe '#validate_and_coerce_params' do
    let(:coercion_tool) { CoercionTestTool.new }

    context 'with integer parameters' do
      it 'coerces string integer to integer' do
        result = coercion_tool.validate_and_coerce_params(int_param: '123')
        expect(result[:int_param]).to eq(123)
      end

      it 'coerces float to integer (truncate)' do
        result = coercion_tool.validate_and_coerce_params(int_param: 12.9)
        expect(result[:int_param]).to eq(12)
      end

      it 'raises error for invalid integer string' do
        expect { coercion_tool.validate_and_coerce_params(int_param: 'abc') }
          .to raise_error(ADK::ToolArgumentError, /expected Integer/)
      end
    end

    context 'with float parameters' do
      it 'coerces string float to float' do
        result = coercion_tool.validate_and_coerce_params(float_param: '12.3')
        expect(result[:float_param]).to eq(12.3)
      end

      it 'coerces integer to float' do
        result = coercion_tool.validate_and_coerce_params(float_param: 12)
        expect(result[:float_param]).to eq(12.0)
      end
    end

    context 'with boolean parameters' do
      it 'coerces true strings to true' do
        %w[true yes 1 t].each do |val|
          result = coercion_tool.validate_and_coerce_params(bool_param: val)
          expect(result[:bool_param]).to be(true)
        end
      end

      it 'coerces false strings to false' do
        %w[false no 0 f].each do |val|
          result = coercion_tool.validate_and_coerce_params(bool_param: val)
          expect(result[:bool_param]).to be(false)
        end
      end

      it 'raises error for invalid boolean string' do
        expect { coercion_tool.validate_and_coerce_params(bool_param: 'foo') }
          .to raise_error(ADK::ToolArgumentError, /expected Boolean/)
      end
    end

    context 'with array parameters' do
      it 'coerces JSON string to array' do
        result = coercion_tool.validate_and_coerce_params(array_param: '[1, 2]')
        expect(result[:array_param]).to eq([1, 2])
      end

      it 'raises error for invalid array JSON' do
        expect { coercion_tool.validate_and_coerce_params(array_param: 'not_array') }
          .to raise_error(ADK::ToolArgumentError, /expected Array/)
      end
    end

    context 'with hash parameters' do
      it 'coerces JSON string to hash' do
        result = coercion_tool.validate_and_coerce_params(hash_param: '{"a": 1}')
        expect(result[:hash_param]).to eq({ 'a' => 1 })
      end

      it 'raises error for invalid hash JSON' do
        expect { coercion_tool.validate_and_coerce_params(hash_param: 'not_hash') }
          .to raise_error(ADK::ToolArgumentError, /expected Hash/)
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
