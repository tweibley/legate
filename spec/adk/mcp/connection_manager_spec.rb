# frozen_string_literal: true

require 'spec_helper'
require 'adk/mcp/connection_manager'

RSpec.describe ADK::Mcp::ConnectionManager do
  let(:tool_registry) { instance_double(ADK::ToolRegistry) }
  let(:selected_tool_names) { %i[calculator weather] }
  let(:servers_config) do
    [
      { 'type' => 'stdio', 'command' => 'npx', 'args' => ['-y', '@modelcontextprotocol/server-math'] },
      { 'type' => 'sse', 'url' => 'http://localhost:3000' }
    ]
  end

  subject(:manager) do
    described_class.new(
      servers_config: servers_config,
      tool_registry: tool_registry,
      selected_tool_names: selected_tool_names
    )
  end

  let(:mock_client_stdio) { instance_double(ADK::Mcp::Client, connect: true, list_tools: [], disconnect: true) }
  let(:mock_client_sse) { instance_double(ADK::Mcp::Client, connect: true, list_tools: [], disconnect: true) }

  before do
    allow(ADK::Mcp::Client).to receive(:new).with(hash_including(type: :stdio)).and_return(mock_client_stdio)
    allow(ADK::Mcp::Client).to receive(:new).with(hash_including(type: :sse)).and_return(mock_client_sse)
  end

  describe '#initialize' do
    it 'initializes with correct attributes' do
      expect(manager.instance_variable_get(:@servers_config)).to eq(servers_config)
      expect(manager.instance_variable_get(:@tool_registry)).to eq(tool_registry)
      expect(manager.instance_variable_get(:@selected_tool_names)).to eq(selected_tool_names)
      expect(manager.clients).to be_empty
    end
  end

  describe '#connect' do
    it 'creates clients and connects to valid servers' do
      expect(ADK::Mcp::Client).to receive(:new).twice
      expect(mock_client_stdio).to receive(:connect)
      expect(mock_client_sse).to receive(:connect)

      manager.connect

      expect(manager.clients).to contain_exactly(mock_client_stdio, mock_client_sse)
    end

    it 'skips servers with unsupported types' do
      invalid_config = [{ 'type' => 'invalid', 'url' => 'foo' }]
      manager_invalid = described_class.new(
        servers_config: invalid_config,
        tool_registry: tool_registry,
        selected_tool_names: selected_tool_names
      )

      expect(ADK::Mcp::Client).not_to receive(:new)
      manager_invalid.connect
      expect(manager_invalid.clients).to be_empty
    end

    it 'discovers and registers tools after connection' do
      tools_list = [
        { name: 'calculator', description: 'Math tool' },
        { name: 'weather', description: 'Weather tool' },
        { name: 'unused', description: 'Unused tool' }
      ]
      allow(mock_client_stdio).to receive(:list_tools).and_return(tools_list)

      expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema)
        .with(tools_list[0], mock_client_stdio, tool_registry)
      expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema)
        .with(tools_list[1], mock_client_stdio, tool_registry)
      expect(ADK::Mcp::ToolWrapper).not_to receive(:from_mcp_schema)
        .with(tools_list[2], any_args)

      manager.connect
    end

    it 'handles connection errors gracefully' do
      allow(mock_client_stdio).to receive(:connect).and_raise(ADK::Mcp::ConnectionError.new('Failed'))

      expect(ADK.logger).to receive(:error).with(/Failed to connect/)

      manager.connect

      # Should still contain the client even if it failed?
      # The original implementation didn't add it to @mcp_clients if connect failed.
      expect(manager.clients).not_to include(mock_client_stdio)
      expect(manager.clients).to include(mock_client_sse)
    end
  end

  describe '#disconnect' do
    before do
      manager.connect
    end

    it 'disconnects all clients and clears the list' do
      expect(mock_client_stdio).to receive(:disconnect)
      expect(mock_client_sse).to receive(:disconnect)

      manager.disconnect

      expect(manager.clients).to be_empty
    end

    it 'handles errors during disconnect gracefully' do
      allow(mock_client_stdio).to receive(:disconnect).and_raise(StandardError.new('Error'))
      expect(ADK.logger).to receive(:error).with(/Error disconnecting MCP client/)

      manager.disconnect
      expect(manager.clients).to be_empty
    end
  end
end
