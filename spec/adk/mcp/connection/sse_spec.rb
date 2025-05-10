# File: spec/adk/mcp/connection/sse_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'net/http'
require 'adk/mcp/connection/sse'
require 'adk/mcp/error'
require 'adk' # For logger
require 'stringio' # For mocking streams

RSpec.describe ADK::Mcp::Connection::Sse do
  let(:base_url) { 'http://localhost:9292/mcp' } # Note: No trailing slash
  # URIs used for mocking Net::HTTP calls
  let(:sse_uri) { URI.parse('http://localhost:9292/mcp/sse') } # Correct expected URI
  let(:message_uri) { URI.parse('http://localhost:9292/mcp/messages') } # Correct expected URI
  let(:connection) { described_class.new(url: base_url) }
  let(:logger_spy) { spy('Logger') }
  let(:mock_http) { instance_double(Net::HTTP) }
  let(:mock_response) { instance_double(Net::HTTPResponse, code: '200', message: 'OK') }

  before do
    allow(ADK).to receive(:logger).and_return(logger_spy)
    # Stub Net::HTTP.start with correct host/port for SSE connection
    allow(Net::HTTP).to receive(:start).with(sse_uri.hostname, sse_uri.port, use_ssl: false).and_yield(mock_http)
    # Stub Net::HTTP.new with correct host/port for POST requests
    allow(Net::HTTP).to receive(:new).with(message_uri.hostname, message_uri.port).and_return(mock_http)
    allow(mock_http).to receive(:use_ssl=)
    # General stub for request, specific tests may override
    allow(mock_http).to receive(:request).and_return(mock_response)
  end

  describe '#initialize' do
    it 'parses the base URL and sets SSE/message URIs correctly' do # Renamed test
      expect(connection.instance_variable_get(:@base_uri).to_s).to eq('http://localhost:9292/mcp/') # Should end with slash now
      expect(connection.instance_variable_get(:@sse_uri).to_s).to eq(sse_uri.to_s)
      expect(connection.instance_variable_get(:@message_uri).to_s).to eq(message_uri.to_s)
    end

    it 'logs initialization' do
      connection # Trigger initialization
      expect(logger_spy).to have_received(:info).with(/SSE Connection initialized/)
    end
  end

  describe '#connect' do
    let(:sse_get_request) { instance_double(Net::HTTP::Get) }
    # Use a generic double for the response and mock needed methods
    let(:sse_ok_response) { instance_double('SSE Response', is_a?: true, :[] => 'text/event-stream', code: '200') }

    before do
      allow(Net::HTTP::Get).to receive(:new).with(sse_uri.request_uri).and_return(sse_get_request)
      allow(sse_get_request).to receive(:[]=)

      # Don't set expectations here, just stub the behavior
      allow(mock_http).to receive(:request).with(sse_get_request).and_yield(sse_ok_response)
      allow(sse_ok_response).to receive(:read_body).and_yield('')
      allow(sse_ok_response).to receive(:is_a?).with(Net::HTTPOK).and_return(true)

      # Prevent thread from actually joining in tests
      allow_any_instance_of(Thread).to receive(:join)
      allow(connection).to receive(:process_sse_event) # Stub private method
    end

    it 'establishes an SSE connection and starts reader thread' do
      expect(connection.connect).to be true
      expect(connection.connected?).to be true
      expect(logger_spy).to have_received(:info).with(/SSE connection established/)
      expect(connection.instance_variable_get(:@sse_reader_thread)).to be_a(Thread)
    end

    it 'raises ConnectionError if SSE connection fails (non-200)' do
      bad_response = instance_double('SSE Response', is_a?: false, code: '404', message: 'Not Found',
                                                     :[] => 'text/html')
      allow(bad_response).to receive(:is_a?).with(Net::HTTPOK).and_return(false)
      # Mock the http.request block yield for the error case
      allow(mock_http).to receive(:request).with(sse_get_request).and_yield(bad_response)
      # read_body shouldn't be called in this case
      expect(bad_response).not_to receive(:read_body)
      expect {
        connection.connect
      }.to raise_error(ADK::Mcp::ConnectionError, /Failed to establish SSE connection. Status: 404/)
      expect(connection.connected?).to be false
    end

    it 'raises ConnectionError if SSE connection has wrong content type' do
      wrong_type_response = instance_double('SSE Response', is_a?: true, code: '200', :[] => 'application/json')
      allow(wrong_type_response).to receive(:is_a?).with(Net::HTTPOK).and_return(true)
      # Mock the http.request block yield for the error case
      allow(mock_http).to receive(:request).with(sse_get_request).and_yield(wrong_type_response)
      # read_body shouldn't be called here either
      expect(wrong_type_response).not_to receive(:read_body)
      expect { connection.connect }.to raise_error(ADK::Mcp::ConnectionError, /Content-Type: application\/json/)
      expect(connection.connected?).to be false
    end

    it 'raises ConnectionError on network errors' do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED, 'Connection refused')
      expect { connection.connect }.to raise_error(ADK::Mcp::ConnectionError, /Connection refused/)
      expect(connection.connected?).to be false
    end

    it 'returns true if already connected' do
      connection.connect # Connect first time
      expect(Net::HTTP).to have_received(:start).once # Verify it was called once
      expect(connection.connect).to be true # Second call should return true
      expect(Net::HTTP).to have_received(:start).once # Verify start wasn't called again
    end
  end

  describe '#disconnect' do
    before do
      # Simulate a connected state
      thread_spy = instance_double(Thread, alive?: true, kill: true, join: true)
      connection.instance_variable_set(:@connected, true)
      connection.instance_variable_set(:@sse_reader_thread, thread_spy)
      connection.instance_variable_set(:@http_client, mock_http) # Assume client exists
    end

    it 'kills the reader thread and resets state' do
      thread_spy = connection.instance_variable_get(:@sse_reader_thread)
      expect(thread_spy).to receive(:kill)
      expect(thread_spy).to receive(:join).with(1)

      connection.disconnect

      expect(connection.connected?).to be false
      expect(connection.instance_variable_get(:@sse_reader_thread)).to be_nil
      expect(connection.instance_variable_get(:@http_client)).to be_nil
      expect(connection.notification_queue.empty?).to be true
      expect(logger_spy).to have_received(:info).with('Disconnecting SSE connection...')
    end

    it 'does nothing if not connected' do
      connection.instance_variable_set(:@connected, false)
      connection.instance_variable_set(:@sse_reader_thread, nil)
      thread_spy = instance_double(Thread)
      expect(thread_spy).not_to receive(:kill)
      connection.disconnect
      expect(logger_spy).not_to have_received(:info).with('Disconnecting SSE connection...')
    end
  end

  describe '#send_request' do
    let(:mcp_request_hash) { { jsonrpc: '2.0', method: 'test', id: connection.next_request_id } }
    let(:mcp_request_json) { mcp_request_hash.to_json }
    let(:post_request) { instance_double(Net::HTTP::Post) }
    let(:success_response_body) { { jsonrpc: '2.0', id: mcp_request_hash[:id], result: { success: true } }.to_json }
    let(:mcp_error_response_body) {
      { jsonrpc: '2.0', id: mcp_request_hash[:id], error: { code: -32000, message: 'Server error' } }.to_json
    }

    before do
      # Expect Net::HTTP::Post.new with the *correct* request URI
      allow(Net::HTTP::Post).to receive(:new).with(message_uri.request_uri).and_return(post_request)
      allow(post_request).to receive(:[]=) # Stub header assignment
      allow(post_request).to receive(:body=).with(mcp_request_json) # Stub body assignment
    end

    it 'sends a POST request and returns the parsed successful response' do
      # Mock the response object from http.request
      mock_success_response = instance_double('HTTP Response', is_a?: true, body: success_response_body)
      allow(mock_success_response).to receive(:is_a?).with(Net::HTTPOK).and_return(true)
      allow(mock_http).to receive(:request).with(post_request).and_return(mock_success_response)

      result = connection.send_request(mcp_request_hash)

      expect(result).to eq({ jsonrpc: '2.0', id: mcp_request_hash[:id], result: { success: true } })
      expect(logger_spy).to have_received(:debug).with(/-> \[MCP Client POST\]/)
      expect(logger_spy).to have_received(:debug).with(/<- \[MCP Client POST Response\]/)
    end

    it 'raises ConnectionError for non-200 HTTP responses' do
      mock_fail_response = instance_double('HTTP Response', is_a?: false, code: '500',
                                                            message: 'Internal Server Error', body: 'Server exploded')
      allow(mock_fail_response).to receive(:is_a?).with(Net::HTTPOK).and_return(false)
      allow(mock_http).to receive(:request).with(post_request).and_return(mock_fail_response)

      expect {
        connection.send_request(mcp_request_hash)
      }.to raise_error(ADK::Mcp::ConnectionError, /MCP POST request failed: 500/)
    end

    it 'raises RemoteToolError if non-200 response contains MCP error structure' do
      mock_mcp_error_response = instance_double('HTTP Response', is_a?: false, code: '400', message: 'Bad Request',
                                                                 body: mcp_error_response_body)
      allow(mock_mcp_error_response).to receive(:is_a?).with(Net::HTTPOK).and_return(false)
      allow(mock_http).to receive(:request).with(post_request).and_return(mock_mcp_error_response)

      # Expect RemoteToolError directly now, not wrapped in ConnectionError
      expect { connection.send_request(mcp_request_hash) }.to raise_error(ADK::Mcp::RemoteToolError, /Server error/)
    end

    it 'raises ProtocolError if the successful response body is not valid JSON' do
      mock_bad_json_response = instance_double('HTTP Response', is_a?: true, body: 'not json')
      allow(mock_bad_json_response).to receive(:is_a?).with(Net::HTTPOK).and_return(true)
      allow(mock_http).to receive(:request).with(post_request).and_return(mock_bad_json_response)

      # Expect ProtocolError directly now, not wrapped in ConnectionError
      expect {
        connection.send_request(mcp_request_hash)
      }.to raise_error(ADK::Mcp::ProtocolError,
                       /Failed to parse MCP JSON response/)
    end

    it 'raises ConnectionError on network errors' do
      allow(mock_http).to receive(:request).with(post_request).and_raise(Errno::ECONNREFUSED, 'Connection refused')
      expect {
        connection.send_request(mcp_request_hash)
      }.to raise_error(ADK::Mcp::ConnectionError, /Connection refused/)
    end
  end

  describe '#read_notification' do
    before do
      connection.instance_variable_set(:@connected, true)
      connection.instance_variable_set(:@notification_queue, Queue.new)
    end

    it 'returns nil if not connected' do
      connection.instance_variable_set(:@connected, false)
      expect(connection.read_notification).to be_nil
    end

    it 'returns notification from queue if available (non-blocking)' do
      # Create a fresh object for this test
      test_connection = described_class.new(url: base_url)
      test_connection.instance_variable_set(:@connected, true)

      # Get a direct reference to the queue
      queue = test_connection.notification_queue

      # Push a notification onto the queue
      notification = { jsonrpc: '2.0', method: 'notify_test' }
      queue.push(notification)

      # Ensure the connection is marked as connected
      allow(test_connection).to receive(:connected?).and_return(true)

      # Test the method
      expect(test_connection.read_notification(0)).to eq(notification)
    end

    it 'returns nil if queue is empty (non-blocking)' do
      expect(connection.notification_queue.empty?).to be true
      expect(connection.read_notification(0)).to be_nil
    end

    it 'waits for notification with timeout' do
      notification = { jsonrpc: '2.0', method: 'notify_test' }

      # Ensure the connection is marked as connected
      allow(connection).to receive(:connected?).and_return(true)

      # In a real scenario, another thread would push this notification
      # and the read_notification method would wait until it arrives or times out
      Thread.new do
        sleep 0.05 # Short delay
        connection.notification_queue.push(notification)
      end

      # Should wait and receive the notification
      expect(connection.read_notification(0.5)).to eq(notification)
    end

    it 'returns nil when timeout is reached' do
      expect(connection.read_notification(0.01)).to be_nil
    end
  end

  describe '#process_sse_event (private)' do
    it 'parses data field and adds to notification queue' do
      event_string = "data: {\"jsonrpc\":\"2.0\",\"method\":\"test_notify\",\"params\":{\"value\":1}}\n\n"
      connection.send(:process_sse_event, event_string)
      expect(connection.notification_queue.pop(true)).to eq({ jsonrpc: '2.0', method: 'test_notify',
                                                              params: { value: 1 } })
    end

    it 'parses multi-line data fields' do
      # Correct multi-line SSE format:
      event_string = "data: {\"jsonrpc\":\"2.0\",\n" \
                   + "data: \"method\":\"test_notify\",\n" \
                   + "data: \"params\":{\"value\":1}}\n\n"
      connection.send(:process_sse_event, event_string)
      expect(connection.notification_queue.pop(true)).to eq({ jsonrpc: '2.0', method: 'test_notify',
                                                              params: { value: 1 } })
    end

    it 'handles event field (but ignores it for queueing)' do
      event_string = "event: resourceUpdate\ndata: {\"uri\":\"test\"}\n\n"
      connection.send(:process_sse_event, event_string)
      expect(connection.notification_queue.pop(true)).to eq({ uri: 'test' })
      # Verify event type was logged if debugging
      expect(logger_spy).to have_received(:debug).with(/Parsed SSE notification \(event: resourceUpdate\)/)
    end

    it 'ignores comments' do
      event_string = ": this is a comment\ndata: {\"data\":true}\n\n"
      connection.send(:process_sse_event, event_string)
      expect(connection.notification_queue.pop(true)).to eq({ data: true })
    end

    it 'logs error for invalid JSON in data field' do
      event_string = "data: not valid json\n\n"
      connection.send(:process_sse_event, event_string)
      expect(logger_spy).to have_received(:error).with(/Failed to parse JSON from SSE data/)
      expect(connection.notification_queue.empty?).to be true
    end
  end

  describe '#next_request_id' do
    it 'increments request ID' do
      expect(connection.next_request_id).to eq(1)
      expect(connection.next_request_id).to eq(2)
    end
  end
end
