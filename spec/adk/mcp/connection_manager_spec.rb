# frozen_string_literal: true

require 'rspec'
require 'adk/mcp/connection_manager'

RSpec.describe ADK::Mcp::ConnectionManager do
  let(:logger) { instance_double(Logger, info: nil, error: nil, warn: nil) }
  let(:manager) { described_class.new(configs, logger) }

  context 'with valid configs' do
    let(:configs) do
      [
        { type: 'stdio', command: 'echo', args: ['hello'] },
        { type: 'sse', url: 'http://localhost:8080' }
      ]
    end

    describe '#initialize' do
      it 'parses and normalizes configs' do
        expect(manager.instance_variable_get(:@configs).size).to eq(2)
        expect(manager.instance_variable_get(:@configs).first[:type]).to eq(:stdio)
      end
    end

    describe '#connect_all' do
      let(:client_double) { instance_double(ADK::Mcp::Client, connect: true) }

      before do
        allow(ADK::Mcp::Client).to receive(:new).and_return(client_double)
      end

      it 'connects to all servers and yields clients' do
        expect(ADK::Mcp::Client).to receive(:new).twice
        expect(client_double).to receive(:connect).twice

        yielded_clients = []
        manager.connect_all do |client|
          yielded_clients << client
        end

        expect(yielded_clients.size).to eq(2)
        expect(manager.active_clients.size).to eq(2)
      end

      it 'handles connection errors gracefully' do
        allow(client_double).to receive(:connect).and_raise(StandardError.new('Connection failed'))

        expect(logger).to receive(:error).with(/Failed to connect/).twice
        manager.connect_all
        expect(manager.active_clients).to be_empty
      end
    end

    describe '#disconnect_all' do
      let(:client_double) { instance_double(ADK::Mcp::Client, connect: true, disconnect: true) }

      before do
        allow(ADK::Mcp::Client).to receive(:new).and_return(client_double)
        manager.connect_all
      end

      it 'disconnects all clients and clears the list' do
        expect(client_double).to receive(:disconnect).twice
        manager.disconnect_all
        expect(manager.active_clients).to be_empty
      end
    end
  end

  context 'with invalid configs' do
    let(:configs) { [{ type: 'unknown' }] }

    it 'logs error and ignores invalid config' do
      expect(logger).to receive(:error).with(/Unsupported MCP server type/)
      expect(manager.instance_variable_get(:@configs)).to be_empty
    end
  end

  context 'with JSON string config' do
    let(:configs) { '[{"type": "stdio", "command": "echo"}]' }

    it 'parses JSON string correctly' do
      expect(manager.instance_variable_get(:@configs).size).to eq(1)
      expect(manager.instance_variable_get(:@configs).first[:type]).to eq(:stdio)
    end
  end
end
