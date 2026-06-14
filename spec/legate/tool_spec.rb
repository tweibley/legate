# frozen_string_literal: true

# File: spec/legate/tool_spec.rb
require 'spec_helper'

# --- Dummy Tools defined globally ---

# Define a dummy class using the DEPRECATED method
class DummyTestToolForRegistration < Legate::Tool
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
class DummyDslTool < Legate::Tool
  tool_description 'A dummy tool for testing define_metadata replacement'
  parameter :p1, type: :string
  # Implicit name: dummy_dsl_tool
  def perform_execution(params, context); end
end

# Define DummyTestTool used by most tests at the top level
unless defined?(DummyTestTool)
  class DummyTestTool < Legate::Tool
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

RSpec.describe Legate::Tool do
  # Create a registry instance for tests that might need it (though many operate on the instance directly)
  let(:registry) { Legate::ToolRegistry.new }
  let(:dummy_registry) { Legate::ToolRegistry.new } # Registry for context

  let(:tool_instance) { DummyTestTool.new }
  let(:params) { { req: 'value' } }
  let(:context) { Legate::ToolContext.new(session_id: 's', user_id: 'u', app_name: 'a', tool_registry: dummy_registry) }

  # --- Removed Global Registration Setup ---
  # before(:context) do
  #   ...
  # end

  # --- Cleanup after context (Keep commented out unless needed) ---
  # after(:context) do
  # If necessary, unregister the tool
  # Legate::ToolRegistry.unregister(:dummy)
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
      expect { tool_instance.execute({}, context) }.to raise_error(Legate::Error, /Missing required parameters for tool 'dummy': req/)
    end

    it 'handles context being nil (for potential backward compatibility)' do
      expect { tool_instance.execute(params, nil) }.not_to raise_error
      expect(tool_instance.received_context).to be_nil
    end

    context 'when perform_execution is not implemented' do
      let(:incomplete_tool_class) do
        Class.new(Legate::Tool) do
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

  describe 'ToolResult normalization' do
    let(:typed_tool) do
      Class.new(Legate::Tool) do
        self.explicit_tool_name = :typed
        tool_description 'returns a ToolResult'
        def perform_execution(_params, _ctx) = Legate::ToolResult.success('typed value')
      end.new
    end

    let(:hash_tool) do
      Class.new(Legate::Tool) do
        self.explicit_tool_name = :hashy
        tool_description 'returns a hash'
        def perform_execution(_params, _ctx) = { status: :success, result: 'hash value' }
      end.new
    end

    it 'normalizes a returned ToolResult to the canonical hash' do
      expect(typed_tool.execute({})).to eq(status: :success, result: 'typed value')
    end

    it 'passes a returned hash through unchanged' do
      expect(hash_tool.execute({})).to eq(status: :success, result: 'hash value')
    end
  end

  describe 'parameter type coercion' do
    let(:coercion_tool) do
      Class.new(Legate::Tool) do
        self.explicit_tool_name = :coercer
        tool_description 'coerces'
        parameter :n, type: :integer, required: false
        parameter :s, type: :string, required: false
        def perform_execution(params, _ctx) = { status: :success, result: params }
      end.new
    end

    it 'parses integer strings as base 10 (not octal/hex)' do
      expect(coercion_tool.send(:coerce_value, '010', :integer)).to eq(10)
      # "0x1f" is not valid base 10 -> rejected, rather than silently read as 31.
      expect { coercion_tool.send(:coerce_value, '0x1f', :integer) }.to raise_error(Legate::ToolArgumentError)
    end

    it 'truncates numeric input to integer' do
      expect(coercion_tool.send(:coerce_value, 123.9, :integer)).to eq(123)
    end

    it 'rejects an Array/Hash for a :string parameter instead of producing inspect-garbage' do
      expect { coercion_tool.send(:coerce_value, [1, 2], :string) }.to raise_error(Legate::ToolArgumentError, /expected String/)
      expect { coercion_tool.send(:coerce_value, { a: 1 }, :string) }.to raise_error(Legate::ToolArgumentError, /expected String/)
    end

    it 'wraps a coercion failure with the parameter and tool name' do
      expect { coercion_tool.send(:validate_and_coerce_params, { n: 'not-a-number' }) }
        .to raise_error(Legate::ToolArgumentError, /Parameter 'n' for tool 'coercer'.*expected Integer/)
    end
  end

  describe '#validate_params' do
    it 'does not raise error if required parameters are present' do
      expect { tool_instance.validate_params(req: 'val') }.not_to raise_error
    end

    it 'raises error if required parameters are missing' do
      expect { tool_instance.validate_params({}) }.to raise_error(Legate::Error, /Missing required parameters for tool 'dummy': req/)
    end
  end

  describe '.define_metadata and tool registration' do
    # Classes are now defined globally above

    # We might need to reset before this context if other tests leave registrations behind
    before(:all) do
      Legate::GlobalToolManager.reset!
      # Manually trigger registration IF defining globally doesn't work as expected
      # Legate::GlobalToolManager.register_tool(DummyTestToolForRegistration)
      # Legate::GlobalToolManager.register_tool(DummyDslTool)
    end

    after(:all) do
      Legate::GlobalToolManager.reset!
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
      Legate::GlobalToolManager.reset!
      Legate::GlobalToolManager.register_tool(DummyTestToolForRegistration)
      Legate::GlobalToolManager.register_tool(DummyDslTool)

      # Ensure registration happened
      expect(Legate::GlobalToolManager.find_class(:reg_test_tool)).to eq(DummyTestToolForRegistration)
      expect(Legate::GlobalToolManager.find_class(:dummy_dsl_tool)).to eq(DummyDslTool)
    end
  end
end
