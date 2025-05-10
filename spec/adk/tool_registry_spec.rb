# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool_registry'
require 'adk/tool'
require 'adk' # For logger

# --- Mock Tool Classes ---
class RegistryMockTool < ADK::Tool
  self.explicit_tool_name = :registry_mock
  tool_description 'Registry Mock Tool Desc'
  parameter :p1, required: true
  def perform_execution(params, context); { status: :success, result: "Mock p1: #{params[:p1]}" }; end
end

class RegistryMockToolNoMeta < ADK::Tool; end

class RegistryErrorTool < ADK::Tool
  self.explicit_tool_name = :registry_error_tool
  def initialize
    raise StandardError, 'Init error!'
  end

  def perform_execution(params, context); end
end
# --- End Mock Tool Classes ---

RSpec.describe ADK::ToolRegistry do
  subject(:registry) { described_class.new }
  let(:logger_spy) { spy('Logger') }

  before do
    # Stub the ADK logger for registry instance
    # Note: ToolRegistry uses ADK.logger, so we stub the main one
    allow(ADK).to receive(:logger).and_return(logger_spy)
  end

  describe '#initialize' do
    it 'starts with an empty tool set' do
      expect(registry.instance_variable_get(:@tools)).to be_empty
    end
  end

  describe '#register' do
    it 'registers a valid tool class' do
      expect(registry.register(:registry_mock, RegistryMockTool)).to be true
      expect(registry.find_class(:registry_mock)).to eq(RegistryMockTool)
      expect(registry.instance_variable_get(:@tools).size).to eq(1)
      expect(logger_spy).to have_received(:info).with(/Registering tool 'registry_mock'/)
    end

    it 'warns and overwrites when registering a tool with the same name' do
      registry.register(:registry_mock, RegistryMockTool) # Initial registration
      class RegistryMockToolV2 < ADK::Tool; end # A different class
      expect(logger_spy).to receive(:warn).with(/Tool 'registry_mock' is already registered.*Overwriting with class RegistryMockToolV2/)
      expect(registry.register(:registry_mock, RegistryMockToolV2)).to be true # Overwriting returns true
      expect(registry.instance_variable_get(:@tools).size).to eq(1)
      expect(registry.find_class(:registry_mock)).to eq(RegistryMockToolV2)
    end

    # Test for uncovered line 23-24
    it 'returns false and logs error if class is not an ADK::Tool subclass' do
      expect(logger_spy).to receive(:error).with(/Attempted to register non-tool class: String.*for name 'not_a_tool'/)
      expect(registry.register(:not_a_tool, String)).to be false
      expect(registry.instance_variable_get(:@tools)).to be_empty
    end
  end

  describe '#find_class' do
    before { registry.register(:registry_mock, RegistryMockTool) }

    it 'returns the class for a registered tool symbol' do
      expect(registry.find_class(:registry_mock)).to eq(RegistryMockTool)
    end

    it 'returns the class for a registered tool string (converted to symbol)' do
      expect(registry.find_class('registry_mock')).to eq(RegistryMockTool)
    end

    it 'returns nil for an unregistered tool' do
      expect(registry.find_class(:nonexistent)).to be_nil
    end
  end

  describe '#create_instance' do
    before do
      registry.register(:registry_mock, RegistryMockTool)
      registry.register(:registry_error_tool, RegistryErrorTool)
    end

    it 'creates an instance of a registered tool' do
      instance = registry.create_instance(:registry_mock)
      expect(instance).to be_a(RegistryMockTool)
    end

    it 'returns nil for an unregistered tool' do
      expect(registry.create_instance(:nonexistent)).to be_nil
    end
  end

  describe '#list_tools' do
    before do
      registry.register(:registry_mock, RegistryMockTool)
      registry.register(:registry_error_tool, RegistryErrorTool)
    end

    it 'returns metadata for registered tools' do
      metadata = registry.list_tools
      expect(metadata.size).to eq(2)
      # Need to fetch metadata from the mock classes correctly
      expect(metadata).to include(RegistryMockTool.tool_metadata)
      expect(metadata).to include(RegistryErrorTool.tool_metadata)
    end

    it 'returns empty array if no tools are registered' do
      empty_registry = described_class.new
      expect(empty_registry.list_tools).to eq([])
    end

    it 'sorts metadata by tool name symbol' do
      clean_registry = described_class.new
      # Register using the names defined IN the tool classes
      clean_registry.register(:registry_mock, RegistryMockTool) # name: :registry_mock
      clean_registry.register(:registry_error_tool, RegistryErrorTool) # name: :registry_error_tool
      metadata = clean_registry.list_tools
      # Expected sort order based on the explicit names
      expect(metadata.map { |m| m[:name] }).to eq([:registry_error_tool, :registry_mock])
    end
  end
end
