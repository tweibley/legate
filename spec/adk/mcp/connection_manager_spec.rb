# frozen_string_literal: true

require 'spec_helper'
require 'adk/mcp/connection_manager'

RSpec.describe ADK::Mcp::ConnectionManager do
  let(:logger) { instance_double(Logger, info: nil, error: nil, debug: nil) }
  let(:manager) { described_class.new(logger) }
  let(:config) { { 'type' => 'stdio', 'command' => 'echo' } }
  let(:client) { instance_double(ADK::Mcp::Client, connect: true, disconnect: true) }

  before do
    allow(ADK::Mcp::Client).to receive(:new).and_return(client)
  end

  describe '#connect_all' do
    it 'connects clients for each config' do
      manager.connect_all([config])
      expect(ADK::Mcp::Client).to have_received(:new).with(type: :stdio, command: 'echo')
      expect(client).to have_received(:connect)
      expect(manager.clients).to include(client)
    end

    it 'handles connection errors gracefully' do
      allow(client).to receive(:connect).and_raise(StandardError, 'Connection failed')
      manager.connect_all([config])
      expect(logger).to have_received(:error).with(/Connection failed/)
    end
  end

  describe '#disconnect_all' do
    it 'disconnects all clients' do
      manager.clients << client
      manager.disconnect_all
      expect(client).to have_received(:disconnect)
      expect(manager.clients).to be_empty
    end
  end
end
