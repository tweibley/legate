# frozen_string_literal: true

require 'spec_helper'
require 'adk/mcp/connection_manager'
require 'adk/mcp/client'
require 'adk/mcp/tool_wrapper'
require 'adk/tool_registry'

RSpec.describe ADK::Mcp::ConnectionManager do
  let(:tool_registry) { instance_double(ADK::ToolRegistry) }
  let(:allowed_tool_names) { %i[tool_a tool_b] }
  let(:manager) do
    described_class.new(
      tool_registry: tool_registry,
      allowed_tool_names: allowed_tool_names
    )
  end
  let(:logger) { instance_double(Logger) }

  before do
    allow(ADK).to receive(:logger).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
    allow(logger).to receive(:debug)
  end

  describe '#initialize' do
    it 'initializes with tool_registry and allowed_tool_names' do
      expect(manager).to be_a(described_class)
      expect(manager.active_clients).to be_empty
    end
  end

  describe '#connect_all' do
    let(:configs) do
      [
        { 'type' => 'stdio', 'command' => 'cmd1' },
        { 'type' => 'sse', 'url' => 'http://localhost' }
      ]
    end

    let(:client1) { instance_double(ADK::Mcp::Client, connect: true, list_tools: []) }
    let(:client2) { instance_double(ADK::Mcp::Client, connect: true, list_tools: []) }

    before do
      allow(ADK::Mcp::Client).to receive(:new).and_return(client1, client2)
    end

    it 'connects to each server in the config' do
      expect(ADK::Mcp::Client).to receive(:new).with(hash_including(type: :stdio)).ordered
      expect(ADK::Mcp::Client).to receive(:new).with(hash_including(type: :sse)).ordered
      expect(client1).to receive(:connect)
      expect(client2).to receive(:connect)

      manager.connect_all(configs)

      expect(manager.active_clients).to include(client1, client2)
    end

    it 'skips unsupported server types' do
      bad_config = [{ 'type' => 'unsupported' }]
      manager.connect_all(bad_config)
      expect(logger).to have_received(:error).with(/Unsupported MCP server type/)
      expect(manager.active_clients).to be_empty
    end

    context 'when tool discovery happens' do
      let(:tools) do
        [
          { name: 'tool_a', description: 'A tool' },
          { name: 'tool_c', description: 'Not allowed tool' }
        ]
      end

      before do
        allow(client1).to receive(:list_tools).and_return(tools)
      end

      it 'registers only allowed tools' do
        expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema)
          .with(tools[0], client1, tool_registry)

        expect(ADK::Mcp::ToolWrapper).not_to receive(:from_mcp_schema)
          .with(tools[1], any_args)

        manager.connect_all([configs.first])
      end

      it 'logs a debug message for skipped tools' do
        manager.connect_all([configs.first])
        expect(logger).to have_received(:debug).with(/Skipping registration of MCP tool 'tool_c'/)
      end
    end

    context 'when connection fails' do
      before do
        allow(client1).to receive(:connect).and_raise(StandardError, 'Connection failed')
      end

      it 'logs the error and continues' do
        manager.connect_all([configs.first])
        expect(logger).to have_received(:error).with(/Unexpected error connecting to MCP server/)
        expect(manager.active_clients).not_to include(client1)
      end
    end
  end

  describe '#disconnect_all' do
    let(:client1) { instance_double(ADK::Mcp::Client, connect: true, list_tools: []) }

    before do
      allow(ADK::Mcp::Client).to receive(:new).and_return(client1)
      manager.connect_all([{ 'type' => 'stdio', 'command' => 'cmd' }])
    end

    it 'disconnects all active clients and clears the list' do
      expect(client1).to receive(:disconnect)
      manager.disconnect_all
      expect(manager.active_clients).to be_empty
    end

    context 'when disconnection fails' do
      before do
        allow(client1).to receive(:disconnect).and_raise(StandardError, 'Disconnect failed')
      end

      it 'logs the error but still clears the client from list' do
        manager.disconnect_all
        expect(logger).to have_received(:error).with(/Error disconnecting MCP client/)
        expect(manager.active_clients).to be_empty
      end
    end
  end
end
