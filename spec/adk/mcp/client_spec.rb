# File: spec/adk/mcp/client_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/version'
require 'adk/mcp/client'
require 'adk/mcp/connection/stdio' # Need the class for mocking
require 'adk/mcp/connection/sse'   # Add for new tests
require 'adk/mcp/error'
require 'adk/mcp' # For logger

# Define constants needed for tests
ADK::VERSION = '0.1.0' unless defined?(ADK::VERSION)
# Need to access the client's constant
PROTOCOL_VERSION = ADK::Mcp::Client::CLIENT_PROTOCOL_VERSION

RSpec.describe ADK::Mcp::Client do
  let(:command) { 'test_mcp_server' }
  let(:args) { ['--stdio'] }
  let(:connection_params) { { type: :stdio, command: command, args: args } }
  let(:client) { described_class.new(connection_params) }
  let(:logger_spy) { spy('Logger') }

  # Mock connection object
  let(:mock_connection) do
    instance_double(ADK::Mcp::Connection::Stdio,
                    connect: true,
                    disconnect: true,
                    connected?: true,
                    send_request: nil,
                    read_message: nil, # Base mock for read
                    next_request_id: 1)
  end

  before do
    allow(ADK).to receive(:logger).and_return(logger_spy)
    allow(ADK::Mcp::Connection::Stdio).to receive(:new)
      .with(command: command, args: args)
      .and_return(mock_connection)
  end

  describe '#initialize' do
    it 'validates :stdio connection params' do
      expect { described_class.new(type: :stdio, command: 'c') }.not_to raise_error
      expect { described_class.new(type: :stdio) }.to raise_error(ArgumentError, /Missing :command/)
    end

    it 'rejects unsupported connection types' do
      expect {
        described_class.new(type: :http, url: '...')
      }.to raise_error(ArgumentError, /Unsupported connection type/)
    end
  end

  describe '#connect' do
    let(:initialize_request) do
      {
        jsonrpc: '2.0', id: 1, method: 'initialize', params: {
          capabilities: {},
          clientInfo: { name: 'adk-ruby-client', version: ADK::VERSION },
          protocolVersion: PROTOCOL_VERSION
        }
      }
    end
    let(:initialize_response_success) do
      { jsonrpc: '2.0', id: 1, result: { capabilities: { 'server_cap' => true } } }
    end

    before do
      # Reset connection state before each connect test
      client.instance_variable_set(:@connected, false)
      client.instance_variable_set(:@connection, nil)
      allow(mock_connection).to receive(:connected?).and_return(true)
      allow(mock_connection).to receive(:next_request_id).and_return(1)
      # Default stub for successful handshake
      allow(client).to receive(:send_request_and_wait)
        .with(initialize_request, timeout: ADK::Mcp::Connection::Stdio::PROCESS_START_TIMEOUT)
        .and_return(initialize_response_success)
    end

    it 'creates and connects the connection object' do
      expect(ADK::Mcp::Connection::Stdio).to receive(:new).and_return(mock_connection)
      expect(mock_connection).to receive(:connect)
      client.connect
    end

    it 'performs the MCP initialize handshake' do
      expect(mock_connection).to receive(:next_request_id).and_return(1)
      # send_request_and_wait is stubbed, implicitly checking send_request
      expect(client).to receive(:send_request_and_wait)
        .with(initialize_request, timeout: ADK::Mcp::Connection::Stdio::PROCESS_START_TIMEOUT)
        .and_return(initialize_response_success)
      client.connect
    end

    it 'stores server capabilities on successful handshake' do
      client.connect
      expect(client.server_capabilities).to eq({ 'server_cap' => true })
    end

    it 'sets connected state to true' do
      client.connect
      # Need to access ivar because connected? method itself is stubbed initially
      expect(client.instance_variable_get(:@connected)).to be true
    end

    it 'raises ConnectionError and disconnects if connection.connect fails' do
      allow(mock_connection).to receive(:connect).and_raise(ADK::Mcp::ConnectionError, 'Process failed')
      expect(client).to receive(:disconnect)
      expect { client.connect }.to raise_error(ADK::Mcp::ConnectionError, 'Process failed')
    end

    it 'raises ConnectionError and disconnects if handshake response is missing' do
      allow(client).to receive(:send_request_and_wait).and_return(nil)
      expect(client).to receive(:disconnect)
      expect { client.connect }.to raise_error(ADK::Mcp::ConnectionError, /MCP Initialize failed: No response/)
    end

    it 'raises ConnectionError and disconnects if handshake response has no result' do
      allow(client).to receive(:send_request_and_wait).and_return({ jsonrpc: '2.0', id: 1,
                                                                    error: { code: -32000, message: 'Failed' } })
      expect(client).to receive(:disconnect)
      expect {
        client.connect
      }.to raise_error(ADK::Mcp::ConnectionError, /MCP Initialize failed: No response or missing result/)
    end

    it 'raises ConnectionError on unexpected errors during connect' do
      allow(mock_connection).to receive(:connect).and_raise(StandardError, 'Unexpected boom')
      expect(client).to receive(:disconnect)
      expect { client.connect }.to raise_error(ADK::Mcp::ConnectionError, /Unexpected boom/)
    end

    it 'does not reconnect if already connected' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@connection, mock_connection)
      expect(mock_connection).not_to receive(:connect)
      expect(client).not_to receive(:send_request_and_wait)
      expect(client.connect).to be true
    end
  end

  describe '#disconnect' do
    before do
      # Start in a connected state for disconnect tests
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@connection, mock_connection)
      allow(mock_connection).to receive(:disconnect)
    end

    it 'calls disconnect on the connection object' do
      expect(mock_connection).to receive(:disconnect)
      client.disconnect
    end

    it 'resets connected state and capabilities' do
      client.disconnect
      expect(client.instance_variable_get(:@connected)).to be false
      expect(client.server_capabilities).to be_nil
      expect(client.instance_variable_get(:@connection)).to be_nil
    end

    it 'handles errors during connection disconnect' do
      allow(mock_connection).to receive(:disconnect).and_raise('Socket error')
      expect { client.disconnect }.not_to raise_error
      # Check the original logger spy again
      expect(logger_spy).to have_received(:error)
      # Ensure state is still reset
      expect(client.instance_variable_get(:@connected)).to be false
    end
  end

  # Common setup for methods requiring connection
  shared_context 'when connected' do
    before do
      # Ensure client is connected and connection object exists
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@connection, mock_connection)
      allow(client).to receive(:connected?).and_return(true)
    end
  end

  describe '#list_tools' do
    include_context 'when connected'
    let(:list_request) { { jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} } }

    before do
      allow(mock_connection).to receive(:next_request_id).and_return(2)
      # Default stub - specific tests will override
      allow(client).to receive(:send_request_and_wait).with(list_request).and_return(nil)
    end

    it 'raises ConnectionError if not connected' do
      allow(client).to receive(:connected?).and_return(false)
      expect { client.list_tools }.to raise_error(ADK::Mcp::ConnectionError, 'Not connected')
    end

    it 'sends tools/list request and returns tools array on success' do
      success_response = { jsonrpc: '2.0', id: 2, result: { tools: [{ name: 'tool1' }, { name: 'tool2' }] } }
      # Override default stub for this test
      allow(client).to receive(:send_request_and_wait).with(list_request).and_return(success_response)
      expect(client.list_tools).to eq([{ name: 'tool1' }, { name: 'tool2' }])
    end

    it 'raises ProtocolError if result.tools is not an array' do
      invalid_response = { jsonrpc: '2.0', id: 2, result: { tools: 'not_an_array' } }
      expect(client).to receive(:send_request_and_wait).with(list_request).and_return(invalid_response)
      expect { client.list_tools }.to raise_error(ADK::Mcp::ProtocolError, /is not an Array/)
    end

    it 'raises RemoteToolError if server returns an error' do
      error_response = { jsonrpc: '2.0', id: 2, error: { code: -32001, message: 'Server error', data: 'details' } }
      expect(client).to receive(:send_request_and_wait).with(list_request).and_return(error_response)
      expect { client.list_tools }.to raise_error(ADK::Mcp::RemoteToolError, /MCP tools\/list failed: Server error/)
    end

    it 'raises ProtocolError if response is invalid or missing' do
      expect(client).to receive(:send_request_and_wait).with(list_request).and_return(nil) # Timeout case
      expect { client.list_tools }.to raise_error(ADK::Mcp::ProtocolError, /Invalid or missing response/)

      expect(client).to receive(:send_request_and_wait).with(list_request).and_return({ jsonrpc: '2.0', id: 2 }) # Missing result/error
      expect { client.list_tools }.to raise_error(ADK::Mcp::ProtocolError, /Invalid or missing response/)
    end
  end

  describe '#call_tool' do
    include_context 'when connected'
    let(:tool_name) { 'calculator' }
    let(:tool_args) { { operation: 'add', a: 1, b: 2 } }
    let(:call_request) {
      { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: tool_name, arguments: tool_args } }
    }

    before do
      allow(mock_connection).to receive(:next_request_id).and_return(3)
      # Default stub
      allow(client).to receive(:send_request_and_wait).with(call_request).and_return(nil)
    end

    it 'raises ConnectionError if not connected' do
      allow(client).to receive(:connected?).and_return(false)
      expect { client.call_tool(tool_name, tool_args) }.to raise_error(ADK::Mcp::ConnectionError, 'Not connected')
    end

    it 'raises ArgumentError if arguments is not a Hash' do
      expect { client.call_tool(tool_name, [1, 2]) }.to raise_error(ArgumentError, 'Arguments must be a Hash')
    end

    it 'sends tools/call request and returns result on success' do
      success_response = { jsonrpc: '2.0', id: 3, result: 3 }
      allow(client).to receive(:send_request_and_wait).with(call_request).and_return(success_response)
      expect(client.call_tool(tool_name, tool_args)).to eq(3)
    end

    it 'raises RemoteToolError if server returns an error' do
      error_response = { jsonrpc: '2.0', id: 3,
                         error: { code: -32002, message: 'Invalid params', data: { field: 'a' } } }
      allow(client).to receive(:send_request_and_wait).with(call_request).and_return(error_response)
      # Use more flexible regex allowing for different hash representations
      expect { client.call_tool(tool_name, tool_args) }.to raise_error(
        ADK::Mcp::RemoteToolError,
        /Invalid params \(Code: -32002\) Data: .*field.*a/
      )
    end

    it 'raises ProtocolError if response is invalid or missing' do
      expect(client).to receive(:send_request_and_wait).with(call_request).and_return(nil) # Timeout
      expect {
        client.call_tool(tool_name, tool_args)
      }.to raise_error(ADK::Mcp::ProtocolError, /Invalid or missing response/)

      expect(client).to receive(:send_request_and_wait).with(call_request).and_return({ jsonrpc: '2.0', id: 3 }) # Missing result/error
      expect {
        client.call_tool(tool_name, tool_args)
      }.to raise_error(ADK::Mcp::ProtocolError, /Invalid or missing response/)
    end
  end

  # Note: Testing the private send_request_and_wait method directly is complex due to its loop
  # and reliance on the connection's internal queue state. Its behavior is tested indirectly
  # through the public methods (connect, list_tools, call_tool).
end
