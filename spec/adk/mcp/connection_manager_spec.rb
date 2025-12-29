# File: spec/adk/mcp/connection_manager_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/mcp/connection_manager'
require 'adk/mcp/client'
require 'adk/mcp/tool_wrapper'
require 'adk/tool_registry'

RSpec.describe ADK::Mcp::ConnectionManager do
  let(:configs) do
    [
      { 'type' => 'stdio', 'command' => 'server1', 'args' => [] },
      { 'type' => 'sse', 'url' => 'http://localhost:8000/sse' }
    ]
  end
  let(:tool_registry) { instance_double(ADK::ToolRegistry) }
  let(:allowed_tool_names) { [:tool1, :tool2] }
  let(:manager) { described_class.new(configs: configs, tool_registry: tool_registry, allowed_tool_names: allowed_tool_names) }
  let(:logger_spy) { spy('Logger') }

  before do
    allow(ADK).to receive(:logger).and_return(logger_spy)
  end

  describe '#initialize' do
    it 'initializes with correct attributes' do
      expect(manager.clients).to be_empty
    end

    it 'handles empty configs' do
      empty_manager = described_class.new(configs: [], tool_registry: tool_registry, allowed_tool_names: [])
      expect(empty_manager.clients).to be_empty
    end
  end

  describe '#connect_all' do
    let(:client_stdio) { instance_double(ADK::Mcp::Client, connect: true, list_tools: []) }
    let(:client_sse) { instance_double(ADK::Mcp::Client, connect: true, list_tools: []) }

    before do
      allow(ADK::Mcp::Client).to receive(:new).and_return(client_stdio, client_sse)
      allow(client_stdio).to receive(:list_tools).and_return([{ name: 'tool1' }, { name: 'tool3' }])
      allow(client_sse).to receive(:list_tools).and_return([{ name: 'tool2' }])
    end

    it 'connects to all configured servers' do
      expect(client_stdio).to receive(:connect)
      expect(client_sse).to receive(:connect)
      manager.connect_all
      expect(manager.clients).to contain_exactly(client_stdio, client_sse)
    end

    it 'filters and registers allowed tools' do
      expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).with({ name: 'tool1' }, client_stdio, tool_registry)
      expect(ADK::Mcp::ToolWrapper).not_to receive(:from_mcp_schema).with({ name: 'tool3' }, any_args) # Not allowed
      expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).with({ name: 'tool2' }, client_sse, tool_registry)

      manager.connect_all
    end

    it 'handles connection errors gracefully' do
      allow(client_stdio).to receive(:connect).and_raise(ADK::Mcp::ConnectionError, 'Connection failed')

      manager.connect_all

      expect(logger_spy).to have_received(:error).with(/Failed to connect/)
      expect(manager.clients).to contain_exactly(client_sse)
    end
  end

  describe '#disconnect_all' do
    let(:client) { instance_double(ADK::Mcp::Client, connect: true) }

    before do
      allow(ADK::Mcp::Client).to receive(:new).and_return(client)
      allow(client).to receive(:list_tools).and_return([])
      manager.connect_all
    end

    it 'disconnects all clients and clears the list' do
      expect(client).to receive(:disconnect)
      expect(client).to receive(:disconnect)
      manager.disconnect_all
      expect(manager.clients).to be_empty
    end

    it 'handles errors during disconnect' do
      # Since we only have one client in the list (because new() was mocked to return same object),
      # and loop iterates over manager.clients
      allow(client).to receive(:disconnect).and_raise('Socket closed')

      manager.disconnect_all

      expect(logger_spy).to have_received(:error).with(/Error disconnecting MCP client/).at_least(:once)
      expect(manager.clients).to be_empty
    end
  end
end
