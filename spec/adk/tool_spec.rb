# File: spec/adk/tool_spec.rb
require 'spec_helper'

# --- Dummy Tool for Testing Base Class ---
class DummyTestToolForRegistration < ADK::Tool
  # We define metadata *inside* the test context to control when registration happens
end

RSpec.describe ADK::Tool do
  let(:tool_instance) { DummyTestTool.new }
  let(:params) { { req: 'value' } }
  let(:context) { ADK::ToolContext.new(session_id: 's', user_id: 'u', app_name: 'a') }

  # --- Separate setup for registration test ---
  before(:context) do
    # Ensure ToolRegistry is available
    # Define a basic tool class for testing execute/validate
    unless defined?(DummyTestTool)
      class DummyTestTool < ADK::Tool
        define_metadata(name: :dummy, description: 'A dummy tool', parameters: { req: { required: true } })
        attr_reader :received_params, :received_context

        def perform_execution(params, context)
          @received_params = params
          @received_context = context
          { status: :success, result: 'dummy success' }
        end
      end
      # Register it once for other tests
      ADK::ToolRegistry.register(:dummy, DummyTestTool) unless ADK::ToolRegistry.find_class(:dummy)
    end
  end

  # --- Cleanup after context ---
  # after(:context) do
  # If necessary, unregister the tool
  # ADK::ToolRegistry.unregister(:dummy)
  # end

  describe '#execute' do
    it 'validates parameters before calling perform_execution' do
      expect(tool_instance).to receive(:validate_params).with(params).ordered.and_call_original
      expect(tool_instance).to receive(:perform_execution).with(params, context).ordered.and_call_original
      tool_instance.execute(params, context)
    end

    it 'passes parameters and context to perform_execution' do
      tool_instance.execute(params, context)
      expect(tool_instance.received_params).to eq(params)
      expect(tool_instance.received_context).to eq(context)
    end

    it 'raises error if required parameters are missing' do
      expect { tool_instance.execute({}, context) }.to raise_error(ADK::Error, /Missing required parameters: req/)
    end

    it 'handles context being nil (for potential backward compatibility)' do
      expect { tool_instance.execute(params, nil) }.not_to raise_error
      expect(tool_instance.received_context).to be_nil
    end
  end

  describe '#validate_params' do
    it 'does not raise error if required parameters are present' do
      expect { tool_instance.validate_params(req: 'val') }.not_to raise_error
    end

    it 'raises error if required parameters are missing' do
      expect { tool_instance.validate_params({}) }.to raise_error(ADK::Error, /Missing required parameters: req/)
    end
  end

  describe '.define_metadata and tool registration' do # Changed describe block name
    it 'stores metadata correctly' do
      # Use the pre-defined DummyTestTool for this check
      expect(DummyTestTool.tool_name).to eq(:dummy)
      expect(DummyTestTool.description).to eq('A dummy tool')
      expect(DummyTestTool.parameters_definition).to eq({ req: { required: true } })
    end

    it 'triggers registration when define_metadata is called' do
      # Use a separate class defined *within* this test context
      tool_name_for_test = :dummy_registration_test

      # Expect register to be called when define_metadata is executed below
      expect(ADK::ToolRegistry).to receive(:register).with(tool_name_for_test, DummyTestToolForRegistration)

      # Define metadata *here* to trigger the registration call
      DummyTestToolForRegistration.define_metadata(
        name: tool_name_for_test,
        description: 'Test registration',
        parameters: {}
      )
    end
  end
end
