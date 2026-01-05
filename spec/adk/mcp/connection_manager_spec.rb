# frozen_string_literal: true

require 'spec_helper'
require 'adk/mcp/connection_manager'
require 'adk/mcp/client'

RSpec.describe ADK::Mcp::ConnectionManager do
  let(:mock_tool_registry) { instance_double(ADK::ToolRegistry) }
  let(:mcp_servers_config) do
    [
      { type: 'stdio', command: 'test_cmd', args: ['arg1'] },
      { type: 'sse', url: 'http://localhost:8000/sse' }
    ]
  end
  let(:allowed_tool_names) { Set.new([:tool1, :tool2]) }

  subject { described_class.new(mcp_servers_config, mock_tool_registry, allowed_tool_names) }

  describe '#initialize' do
    it 'initializes with config, registry, and allowed names' do
      expect(subject.clients).to be_empty
    end

    it 'handles nil config' do
      manager = described_class.new(nil, mock_tool_registry)
      expect(manager.clients).to be_empty
    end
  end

  describe '#connect_all' do
    let(:mock_client) { instance_double(ADK::Mcp::Client) }

    before do
      allow(ADK::Mcp::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:connect)
      allow(mock_client).to receive(:list_tools).and_return([])
    end

    it 'connects to all configured servers' do
      expect(ADK::Mcp::Client).to receive(:new).with(hash_including(type: :stdio)).ordered
      expect(ADK::Mcp::Client).to receive(:new).with(hash_including(type: :sse)).ordered
      expect(mock_client).to receive(:connect).twice

      subject.connect_all
      expect(subject.clients.size).to eq(2)
    end

    it 'skips unsupported types' do
      bad_config = [{ type: 'unknown' }]
      manager = described_class.new(bad_config, mock_tool_registry)

      expect(ADK.logger).to receive(:error).with(/Unsupported MCP server type/)
      manager.connect_all
      expect(manager.clients).to be_empty
    end

    it 'handles connection errors gracefully' do
      allow(mock_client).to receive(:connect).and_raise(ADK::Mcp::ConnectionError.new('Connection failed'))

      expect(ADK.logger).to receive(:error).with(/Failed to connect or handshake/).twice
      subject.connect_all
    end
  end

  describe '#disconnect_all' do
    let(:mock_client) { instance_double(ADK::Mcp::Client) }

    before do
      allow(ADK::Mcp::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:connect)
      allow(mock_client).to receive(:list_tools).and_return([])
      subject.connect_all
    end

    it 'disconnects all clients' do
      expect(mock_client).to receive(:disconnect).twice
      subject.disconnect_all
      expect(subject.clients).to be_empty
    end

    it 'handles disconnect errors gracefully' do
      allow(mock_client).to receive(:disconnect).and_raise(StandardError.new('Disconnect failed'))
      expect(ADK.logger).to receive(:error).with(/Error disconnecting MCP client/).twice
      subject.disconnect_all
      expect(subject.clients).to be_empty
    end
  end

  describe 'tool discovery' do
    let(:mock_client) { instance_double(ADK::Mcp::Client) }
    let(:tool_schemas) do
      [
        { name: 'tool1', description: 'desc1' },
        { name: 'tool2', description: 'desc2' },
        { name: 'tool3', description: 'desc3' }
      ]
    end

    before do
      allow(ADK::Mcp::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:connect)
      allow(mock_client).to receive(:list_tools).and_return(tool_schemas)
    end

    it 'registers only allowed tools' do
      expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).with(hash_including(name: 'tool1'), mock_client, mock_tool_registry).twice
      expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).with(hash_including(name: 'tool2'), mock_client, mock_tool_registry).twice
      expect(ADK::Mcp::ToolWrapper).not_to receive(:from_mcp_schema).with(hash_including(name: 'tool3'), any_args)

      subject.connect_all
    end

    it 'registers all tools if no filter provided' do
      manager = described_class.new(mcp_servers_config, mock_tool_registry, nil)

      expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).exactly(6).times # 3 tools * 2 servers

      manager.connect_all
    end
  end
end
