# frozen_string_literal: true

require 'spec_helper'
require 'adk/mcp/connection_manager'

RSpec.describe ADK::Mcp::ConnectionManager do
  let(:tool_registry) { instance_double(ADK::ToolRegistry) }
  let(:allowed_tool_names) { Set.new(%i[tool1 tool2]) }
  let(:configs) { [{ type: 'stdio', command: 'test' }] }
  let(:manager) { described_class.new(configs, tool_registry, allowed_tool_names) }
  let(:logger_double) { spy('Logger') }

  before do
    allow(ADK).to receive(:logger).and_return(logger_double)
  end

  describe '#initialize' do
    it 'sets instance variables correctly' do
      expect(manager.clients).to be_empty
      expect(manager.instance_variable_get(:@configs)).to eq(configs)
      expect(manager.instance_variable_get(:@tool_registry)).to eq(tool_registry)
      expect(manager.instance_variable_get(:@allowed_tool_names)).to eq(allowed_tool_names)
    end
  end

  describe '#connect_all' do
    let(:client_double) { instance_double(ADK::Mcp::Client, connect: true, list_tools: []) }

    before do
      allow(ADK::Mcp::Client).to receive(:new).and_return(client_double)
    end

    it 'connects to configured servers' do
      manager.connect_all
      expect(client_double).to have_received(:connect)
      expect(manager.clients).to include(client_double)
    end

    it 'handles connection errors gracefully' do
      allow(client_double).to receive(:connect).and_raise(ADK::Mcp::ConnectionError.new('Fail'))
      manager.connect_all
      expect(logger_double).to have_received(:error).with(/Failed to connect/)
    end

    it 'validates config type' do
        bad_config = [{ type: 'invalid' }]
        bad_manager = described_class.new(bad_config, tool_registry)
        bad_manager.connect_all
        expect(logger_double).to have_received(:error).with(/Unsupported MCP server type/)
    end

    context 'tool discovery' do
        let(:tools) { [{ name: 'tool1' }, { name: 'tool3' }] }

        before do
            allow(client_double).to receive(:list_tools).and_return(tools)
            allow(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema)
        end

        it 'registers allowed tools' do
            manager.connect_all
            expect(ADK::Mcp::ToolWrapper).to have_received(:from_mcp_schema).with(tools[0], client_double, tool_registry)
        end

        it 'skips disallowed tools' do
            manager.connect_all
            expect(ADK::Mcp::ToolWrapper).not_to have_received(:from_mcp_schema).with(tools[1], client_double, tool_registry)
        end
    end
  end

  describe '#disconnect_all' do
    let(:client_double) { instance_double(ADK::Mcp::Client, disconnect: true) }

    before do
      manager.instance_variable_set(:@clients, [client_double])
    end

    it 'disconnects all clients' do
      manager.disconnect_all
      expect(client_double).to have_received(:disconnect)
      expect(manager.clients).to be_empty
    end

    it 'handles errors during disconnect' do
        allow(client_double).to receive(:disconnect).and_raise(StandardError.new("Boom"))
        manager.disconnect_all
        expect(logger_double).to have_received(:error).with(/Error disconnecting/)
        expect(manager.clients).to be_empty
    end
  end
end
