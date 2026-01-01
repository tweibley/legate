# frozen_string_literal: true

require 'spec_helper'
require 'adk/mcp/connection_manager'
require 'adk/mcp/client'
require 'adk/tool_registry'

RSpec.describe ADK::Mcp::ConnectionManager do
  let(:config) { [{ type: :stdio, command: 'echo', args: ['hello'] }] }
  let(:tool_registry) { instance_double(ADK::ToolRegistry) }
  let(:logger) { instance_double(Logger, info: nil, debug: nil, error: nil) }
  let(:client_double) { instance_double(ADK::Mcp::Client, connect: true, disconnect: true, list_tools: []) }

  subject(:manager) { described_class.new(config: config, tool_registry: tool_registry, logger: logger) }

  before do
    allow(ADK::Mcp::Client).to receive(:new).and_return(client_double)
  end

  describe '#initialize' do
    it 'initializes with correct attributes' do
      expect(manager.instance_variable_get(:@config)).to eq(config)
      expect(manager.instance_variable_get(:@tool_registry)).to eq(tool_registry)
      expect(manager.instance_variable_get(:@clients)).to be_empty
    end
  end

  describe '#connect_all' do
    it 'creates and connects clients for each config' do
      expect(ADK::Mcp::Client).to receive(:new).with(hash_including(type: :stdio)).and_return(client_double)
      expect(client_double).to receive(:connect)

      manager.connect_all
      expect(manager.clients).to include(client_double)
    end

    it 'discovers and registers tools' do
      allow(client_double).to receive(:list_tools).and_return([{ name: 'test_tool' }])
      # We need to stub ADK::Mcp::ToolWrapper.from_mcp_schema if we want to test registration fully
      # or trust the integration. Here we'll mock the internal call or just rely on wrapper behavior if loaded.
      # For unit test isolation, let's mock the wrapper creation or the private method.

      # Mock the wrapper class method to avoid actual tool creation complexity
      wrapper_class = class_double(ADK::Mcp::ToolWrapper).as_stubbed_const
      expect(wrapper_class).to receive(:from_mcp_schema).with(anything, client_double, tool_registry)

      # Ensure tool is selected so it gets registered
      manager_with_selection = described_class.new(
        config: config,
        tool_registry: tool_registry,
        selected_tool_names: [:test_tool],
        logger: logger
      )

      manager_with_selection.connect_all
    end

    it 'handles connection errors gracefully' do
      allow(client_double).to receive(:connect).and_raise(StandardError, 'Connection failed')
      expect(logger).to receive(:error).with(/Unexpected error connecting to MCP server/)

      expect { manager.connect_all }.not_to raise_error
    end
  end

  describe '#disconnect_all' do
    before do
      manager.connect_all
    end

    it 'disconnects all clients and clears the list' do
      expect(client_double).to receive(:disconnect)
      manager.disconnect_all
      expect(manager.clients).to be_empty
    end

    it 'handles disconnect errors gracefully' do
      allow(client_double).to receive(:disconnect).and_raise(StandardError, 'Disconnect failed')
      expect(logger).to receive(:error).with(/Error disconnecting MCP client/)

      expect { manager.disconnect_all }.not_to raise_error
      expect(manager.clients).to be_empty # Should still clear list
    end
  end
end
