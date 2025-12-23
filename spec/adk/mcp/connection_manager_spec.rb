# frozen_string_literal: true

require 'spec_helper'
require 'adk/mcp/connection_manager'

RSpec.describe ADK::Mcp::ConnectionManager do
  let(:tool_registry) { instance_double(ADK::ToolRegistry, object_id: 12345) }
  let(:mock_client) { instance_double(ADK::Mcp::Client) }
  let(:server_config) { { type: 'stdio', command: 'test' } }
  let(:config) { [server_config] }
  let(:manager) { described_class.new(config) }

  before do
    allow(ADK).to receive(:logger).and_return(
      instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil)
    )
    allow(ADK::Mcp::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:connect)
    allow(mock_client).to receive(:disconnect)
    allow(mock_client).to receive(:list_tools).and_return([])
  end

  describe '#initialize' do
    it 'normalizes array config' do
      expect(manager.config).to eq([server_config])
    end

    it 'normalizes string config' do
      json_config = JSON.generate([server_config])
      mgr = described_class.new(json_config)
      expect(mgr.config).to eq([server_config.transform_keys(&:to_s)]) # JSON parse keys are strings
    end

    it 'handles invalid string config' do
      mgr = described_class.new("invalid json")
      expect(mgr.config).to eq([])
    end

    it 'handles nil config' do
      mgr = described_class.new(nil)
      expect(mgr.config).to eq([])
    end
  end

  describe '#connect_all' do
    it 'creates clients and connects' do
      expected_config = server_config.transform_keys(&:to_sym).merge(type: :stdio)
      manager.connect_all(tool_registry)
      expect(ADK::Mcp::Client).to have_received(:new).with(expected_config)
      expect(mock_client).to have_received(:connect)
      expect(manager.clients).to include(mock_client)
    end

    it 'registers tools for connected clients' do
      tool_schema = { name: 'test_tool', description: 'Test' }
      allow(mock_client).to receive(:list_tools).and_return([tool_schema])
      allow(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema)

      manager.connect_all(tool_registry)

      expect(mock_client).to have_received(:list_tools)
      expect(ADK::Mcp::ToolWrapper).to have_received(:from_mcp_schema).with(tool_schema, mock_client, tool_registry)
    end

    it 'filters tools if selected_tool_names is provided' do
      tool1 = { name: 'tool1' }
      tool2 = { name: 'tool2' }
      allow(mock_client).to receive(:list_tools).and_return([tool1, tool2])
      allow(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema)

      manager.connect_all(tool_registry, [:tool1])

      expect(ADK::Mcp::ToolWrapper).to have_received(:from_mcp_schema).with(tool1, mock_client, tool_registry)
      expect(ADK::Mcp::ToolWrapper).not_to have_received(:from_mcp_schema).with(tool2, any_args)
    end

    it 'handles connection errors gracefully' do
      allow(mock_client).to receive(:connect).and_raise(ADK::Mcp::ConnectionError.new('Fail'))

      manager.connect_all(tool_registry)

      expect(manager.clients).to be_empty
    end

    it 'skips unsupported server types' do
      bad_config = [{ type: 'invalid' }]
      mgr = described_class.new(bad_config)
      mgr.connect_all(tool_registry)
      expect(ADK::Mcp::Client).not_to have_received(:new)
    end
  end

  describe '#disconnect_all' do
    it 'disconnects all clients' do
      manager.connect_all(tool_registry)
      manager.disconnect_all
      expect(mock_client).to have_received(:disconnect)
      expect(manager.clients).to be_empty
    end
  end
end
