# File: spec/adk/global_tool_manager_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/global_tool_manager'
require 'adk/tool' # Dependency for tool classes

# --- Mock Tool Classes for Testing ---
class GtmMockTool < ADK::Tool
  define_metadata(name: :gtm_mock, description: 'GTM Mock Tool Desc', parameters: { p1: { required: true } })
  def initialize; end # Simple constructor for testing
end

class GtmMockToolNoMeta < ADK::Tool
  # No metadata defined
end

class GtmMockToolOther < ADK::Tool
  define_metadata(name: :gtm_other, description: 'Other GTM Tool', parameters: {})
  def initialize; end
end

class GtmMockToolWithError < ADK::Tool
  define_metadata(name: :gtm_error_tool, description: 'Errors on init', parameters: {})
  def initialize
    raise StandardError, "Init failed!"
  end
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
      described_class.register_tool(GtmMockTool) # Register first time
      expect(logger_spy).to receive(:warn).with(/Tool name 'gtm_mock' is already registered.*Overwriting/)
      expect { described_class.register_tool(GtmMockTool) } # Re-register same class (idempotent)
        .not_to change { described_class.class_variable_get(:@@defined_tools).count }
      # --- Define metadata for the anonymous class --- >
      anon_class_with_meta = Class.new(GtmMockTool) do
        define_metadata(name: :gtm_mock, description: 'Anon Desc', parameters: {})
      end
      expect { described_class.register_tool(anon_class_with_meta) } # Register different class with same name
        # <-----------------------------------------------
        .not_to change { described_class.class_variable_get(:@@defined_tools).count }
    end

    it 'warns and skips registration if tool class has no name metadata' do
      expect(logger_spy).to receive(:warn).with(/Tool class GtmMockToolNoMeta has no name defined/)
      expect { described_class.register_tool(GtmMockToolNoMeta) }
        .not_to change { described_class.class_variable_get(:@@defined_tools).count }
    end

    it 'warns and skips registration if object is not an ADK::Tool subclass' do
      expect(logger_spy).to receive(:warn).with(/Attempted to register non-tool class: String/)
      expect { described_class.register_tool(String) }
        .not_to change { described_class.class_variable_get(:@@defined_tools).count }
    end
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
      described_class.register_tool(GtmMockToolWithError)
      expect(logger_spy).to receive(:error).with(/Failed to instantiate tool 'gtm_error_tool'.*Init failed!/)
      expect(described_class.create_instance(:gtm_error_tool)).to be_nil
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
      described_class.register_tool(GtmMockToolOther) # name: :gtm_other
      described_class.register_tool(GtmMockTool)      # name: :gtm_mock

      expected_list = [
        { name: :gtm_mock, description: 'GTM Mock Tool Desc', parameters: { p1: { required: true } } },
        { name: :gtm_other, description: 'Other GTM Tool', parameters: {} }
      ]

      expect(described_class.list_all_tools).to eq(expected_list)
    end

    it 'handles tools with missing descriptions or parameters gracefully' do
      # Create a tool class dynamically with minimal metadata
      # --- Provide a default description --- >
      class GtmMinimalTool < ADK::Tool; define_metadata(name: :gtm_minimal, description: ''); end
      # <---------------------------------------
      described_class.register_tool(GtmMinimalTool)

      tools_list = described_class.list_all_tools
      minimal_tool_meta = tools_list.find { |t| t[:name] == :gtm_minimal }

      expect(minimal_tool_meta).not_to be_nil
      expect(minimal_tool_meta[:description]).to eq('')
      expect(minimal_tool_meta[:parameters]).to eq({}) # Parameters should default to empty hash in metadata method
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
