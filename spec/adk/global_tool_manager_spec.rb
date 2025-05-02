# File: spec/adk/global_tool_manager_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/global_tool_manager'
require 'adk/tool' # Dependency for tool classes

# --- Mock Tool Classes for Testing ---
class GtmMockTool < ADK::Tool
  self.explicit_tool_name = :gtm_mock
  tool_description 'GTM Mock Tool Desc'
  parameter :p1, required: true
  def perform_execution(params, context); { status: :success, result: "Mock p1: #{params[:p1]}" }; end
end

class GtmMockToolNoMeta < ADK::Tool; end

class GtmMockToolOther < ADK::Tool
  self.explicit_tool_name = :gtm_other
  tool_description 'Other GTM Tool'
  def perform_execution(params, context); { status: :success, result: 'Other' }; end
end

class GtmMockToolWithError < ADK::Tool
  self.explicit_tool_name = :gtm_error_tool
  tool_description 'Errors on init'
  def initialize
    raise StandardError, "Initialization Error"
  end

  def perform_execution(params, context); { status: :success, result: 'Should not reach' }; end
end
# --- End Mock Tool Classes ---

RSpec.describe ADK::GlobalToolManager do
  let(:logger_spy) { spy('Logger') }

  before do
    # Ensure a clean slate before each test
    described_class.reset!
    # Stub the ADK logger
    allow(ADK).to receive(:logger).and_return(logger_spy)
  end

  # Reset after all tests in this file
  after(:all) do
    described_class.reset!
  end

  describe '.register_tool' do
    it 'registers a valid tool class' do
      expect { described_class.register_tool(GtmMockTool) }
        .to change { described_class.class_variable_get(:@@defined_tools).count }.by(1)
      expect(described_class.find_class(:gtm_mock)).to eq(GtmMockTool)
      expect(logger_spy).to have_received(:debug).with(/Registered tool 'gtm_mock'/)
    end

    it 'warns and overwrites when registering a tool with the same name' do
      described_class.register_tool(GtmMockTool)
      class GtmMockToolDuplicate < ADK::Tool
        self.explicit_tool_name = :gtm_mock
        tool_description 'Anon Desc'
        def perform_execution(params, context); { status: :success, result: 'Duplicate' }; end
      end

      expect(logger_spy).to receive(:warn).with(/GlobalToolManager: Tool name 'gtm_mock' is already registered.*Overwriting with GtmMockToolDuplicate/)
      expect { described_class.register_tool(GtmMockToolDuplicate) }
        .not_to change { described_class.class_variable_get(:@@defined_tools).count }
    end

    it 'registers tool via inferred name even if metadata is explicitly missing' do
      expect { described_class.register_tool(GtmMockToolNoMeta) }
        .to change { described_class.class_variable_get(:@@defined_tools).count }.by(1)
      expect(described_class.find_class(:gtm_mock_tool_no_meta)).to eq(GtmMockToolNoMeta)
    end

    it 'warns and skips registration if object is not an ADK::Tool subclass' do
      expect(logger_spy).to receive(:warn).with(/Attempted to register non-tool class: String/)
      expect { described_class.register_tool(String) }
        .not_to change { described_class.class_variable_get(:@@defined_tools).count }
    end

    it 'uses klass.to_s in warning for anonymous non-tool classes' do
      anon_class = Class.new
      expect(logger_spy).to receive(:warn).with(/Attempted to register non-tool class: #{anon_class.to_s}/)
      expect { described_class.register_tool(anon_class) }
        .not_to change { described_class.class_variable_get(:@@defined_tools).count }
    end

    # Removing the test for the unreachable path where respond_to?(:tool_name) is false
    # it 'infers tool name if class does not respond_to?(:tool_name)' do
    #   ...
    # end
  end

  describe '.find_class' do
    before { described_class.register_tool(GtmMockTool) }

    it 'returns the class for a registered tool symbol' do
      expect(described_class.find_class(:gtm_mock)).to eq(GtmMockTool)
    end

    it 'returns nil for an unregistered tool symbol' do
      expect(described_class.find_class(:non_existent)).to be_nil
    end

    it 'accepts string input and finds the class' do
      expect(described_class.find_class('gtm_mock')).to eq(GtmMockTool)
    end
  end

  describe '.create_instance' do
    before { described_class.register_tool(GtmMockTool) }

    it 'creates an instance of a registered tool' do
      instance = described_class.create_instance(:gtm_mock)
      expect(instance).to be_a(GtmMockTool)
      expect(logger_spy).to have_received(:debug).with("GlobalToolManager: Successfully instantiated tool 'gtm_mock'.")
    end

    it 'returns nil and logs warning for an unregistered tool' do
      expect(logger_spy).to receive(:warn).with(/Attempted to create instance of tool 'non_existent' which is not globally registered/)
      expect(described_class.create_instance(:non_existent)).to be_nil
    end

    it 'returns nil and logs error if tool initialization fails' do
      # Register the tool that errors on init
      described_class.register_tool(GtmMockToolWithError)

      # Call create_instance, it should rescue the init error and return nil
      expect(described_class.create_instance(:gtm_error_tool)).to be_nil

      # Check that the correct error was logged via the logger_spy
      expect(logger_spy).to have_received(:error).with(/GlobalToolManager: Failed to instantiate tool 'gtm_error_tool'.*StandardError - Initialization Error/).ordered
      # Check that a backtrace line was also logged
      expect(logger_spy).to have_received(:error).with(match(/global_tool_manager_spec\.rb.*initialize/)).ordered
    end

    it 'accepts string input and creates an instance' do
      instance = described_class.create_instance('gtm_mock')
      expect(instance).to be_a(GtmMockTool)
    end
  end

  describe '.list_all_tools' do
    it 'returns an empty array when no tools are registered' do
      expect(described_class.list_all_tools).to eq([])
    end

    it 'returns metadata for all registered tools, sorted by name' do
      described_class.register_tool(GtmMockToolOther)
      described_class.register_tool(GtmMockTool)

      expected_list = [
        { name: :gtm_mock, description: 'GTM Mock Tool Desc', parameters: { p1: { required: true } } },
        { name: :gtm_other, description: 'Other GTM Tool', parameters: {} }
      ]

      expect(described_class.list_all_tools).to eq(expected_list)
    end

    it 'handles tools with missing descriptions or parameters gracefully' do
      described_class.reset!
      class GtmMinimalTool < ADK::Tool
        self.explicit_tool_name = :gtm_minimal
      end

      metadata = described_class.list_all_tools
      expect(metadata.size).to eq(1)
    end
  end

  describe '.reset!' do
    it 'clears all registered tools' do
      described_class.register_tool(GtmMockTool)
      expect(described_class.class_variable_get(:@@defined_tools)).not_to be_empty
      described_class.reset!
      expect(described_class.class_variable_get(:@@defined_tools)).to be_empty
    end
  end
end
