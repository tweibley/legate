# frozen_string_literal: true

require 'spec_helper'
require 'adk/mcp/connection_manager'

RSpec.describe ADK::Mcp::ConnectionManager do
  let(:tool_registry) { instance_double(ADK::ToolRegistry) }
  let(:allowed_tools) { Set.new([:tool1, :tool2]) }
  let(:manager) { described_class.new(tool_registry: tool_registry, allowed_tool_names: allowed_tools) }
  let(:mock_client) { instance_double(ADK::Mcp::Client) }

  before do
    allow(ADK.logger).to receive(:info)
    allow(ADK.logger).to receive(:error)
    allow(ADK.logger).to receive(:debug)
  end

  describe '#connect_all' do
    let(:valid_config) { { 'type' => 'stdio', 'command' => 'cmd' } }

    before do
      allow(ADK::Mcp::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:connect)
      allow(mock_client).to receive(:list_tools).and_return([])
    end

    it 'connects to configured servers' do
      expect(ADK::Mcp::Client).to receive(:new).with(hash_including(type: :stdio))
      expect(mock_client).to receive(:connect)

      manager.connect_all([valid_config])
      expect(manager.clients).to include(mock_client)
    end

    it 'handles unsupported types gracefully' do
      invalid_config = { 'type' => 'invalid' }

      expect(ADK::Mcp::Client).not_to receive(:new)
      expect(ADK.logger).to receive(:error).with(/Unsupported MCP server type/)

      manager.connect_all([invalid_config])
    end

    it 'discovers and registers allowed tools' do
      tools = [{ name: 'tool1' }, { name: 'tool3' }]
      allow(mock_client).to receive(:list_tools).and_return(tools)

      # Should register tool1 (allowed) but not tool3 (not allowed)
      expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).with(tools[0], mock_client, tool_registry)
      expect(ADK::Mcp::ToolWrapper).not_to receive(:from_mcp_schema).with(tools[1], any_args)

      manager.connect_all([valid_config])
    end

    it 'handles connection errors gracefully' do
      allow(mock_client).to receive(:connect).and_raise(ADK::Mcp::ConnectionError.new("Fail"))

      expect(ADK.logger).to receive(:error).with(/Failed to connect/)
      manager.connect_all([valid_config])
      expect(manager.clients).to be_empty
    end
  end

  describe '#disconnect_all' do
    before do
      manager.instance_variable_set(:@clients, [mock_client])
    end

    it 'disconnects all clients' do
      expect(mock_client).to receive(:disconnect)
      manager.disconnect_all
      expect(manager.clients).to be_empty
    end

    it 'handles disconnection errors' do
      allow(mock_client).to receive(:disconnect).and_raise(StandardError.new("Fail"))
      expect(ADK.logger).to receive(:error).with(/Error disconnecting MCP client/)

      manager.disconnect_all
      expect(manager.clients).to be_empty # Should still clear list
    end
  end
end
