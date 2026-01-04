# frozen_string_literal: true

require 'spec_helper'
require 'adk/mcp/connection_manager'

RSpec.describe ADK::Mcp::ConnectionManager do
  let(:tool_registry) { instance_double(ADK::ToolRegistry) }
  let(:server_configs) { [] }
  let(:allowed_tool_names) { nil }
  let(:manager) do
    described_class.new(
      server_configs: server_configs,
      tool_registry: tool_registry,
      allowed_tool_names: allowed_tool_names
    )
  end

  before do
    allow(ADK.logger).to receive(:info)
    allow(ADK.logger).to receive(:error)
    allow(ADK.logger).to receive(:debug)
  end

  describe '#initialize' do
    it 'initializes with empty clients list' do
      expect(manager.clients).to be_empty
    end
  end

  describe '#connect_all' do
    context 'when no servers are configured' do
      it 'does nothing' do
        manager.connect_all
        expect(manager.clients).to be_empty
      end
    end

    context 'with valid server configuration' do
      let(:server_configs) { [{ 'type' => 'stdio', 'command' => 'echo', 'args' => ['hello'] }] }
      let(:mock_client) { instance_double(ADK::Mcp::Client, connect: true, list_tools: []) }

      before do
        allow(ADK::Mcp::Client).to receive(:new).and_return(mock_client)
      end

      it 'creates and connects clients' do
        manager.connect_all
        expect(manager.clients).to include(mock_client)
        expect(mock_client).to have_received(:connect)
      end

      it 'calls discover_and_register_tools' do
        expect(mock_client).to receive(:list_tools).and_return([])
        manager.connect_all
      end
    end

    context 'with invalid server type' do
      let(:server_configs) { [{ 'type' => 'invalid_type' }] }

      it 'logs an error and raises McpError inside (caught)' do
        expect(ADK.logger).to receive(:error).with(/Unsupported MCP server type/)
        expect { manager.connect_all }.not_to raise_error
        expect(manager.clients).to be_empty
      end
    end
  end

  describe '#disconnect_all' do
    let(:mock_client) { instance_double(ADK::Mcp::Client) }

    before do
      manager.instance_variable_get(:@clients) << mock_client
    end

    it 'disconnects all clients and clears the list' do
      expect(mock_client).to receive(:disconnect)
      manager.disconnect_all
      expect(manager.clients).to be_empty
    end

    it 'handles errors during disconnection gracefully' do
      allow(mock_client).to receive(:disconnect).and_raise(StandardError, 'fail')
      expect(ADK.logger).to receive(:error).with(/Error disconnecting MCP client/)
      manager.disconnect_all
      expect(manager.clients).to be_empty
    end
  end

  describe 'private #discover_and_register_tools' do
    let(:server_configs) { [{ 'type' => 'stdio', 'command' => 'echo' }] }
    let(:mock_client) { instance_double(ADK::Mcp::Client, connect: true) }
    let(:tool_schemas) do
      [
        { name: 'tool_a', description: 'Tool A' },
        { name: 'tool_b', description: 'Tool B' }
      ]
    end

    before do
      allow(ADK::Mcp::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:list_tools).and_return(tool_schemas)
    end

    context 'when allowed_tool_names is not set (nil)' do
      let(:allowed_tool_names) { nil }

      it 'registers all discovered tools' do
        expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).with(tool_schemas[0], mock_client, tool_registry)
        expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).with(tool_schemas[1], mock_client, tool_registry)
        manager.connect_all
      end
    end

    context 'when allowed_tool_names is set' do
      let(:allowed_tool_names) { [:tool_a] }

      it 'registers only allowed tools' do
        expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).with(tool_schemas[0], mock_client, tool_registry)
        expect(ADK::Mcp::ToolWrapper).not_to receive(:from_mcp_schema).with(tool_schemas[1], any_args)
        manager.connect_all
      end
    end
  end
end
