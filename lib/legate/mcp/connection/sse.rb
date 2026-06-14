# File: lib/legate/mcp/connection/sse.rb
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require_relative '../../errors'

module Legate
  module Mcp
    module Connection
      # Manages a connection to an MCP server via HTTP/SSE.
      # Uses Server-Sent Events (SSE) for server-to-client notifications
      # and standard HTTP POST for client-to-server requests/responses.
      # Automatically reconnects with exponential backoff on stream drops.
      class Sse
        MAX_RECONNECT_ATTEMPTS = 5
        RECONNECT_BASE_DELAY = 1
        RECONNECT_MAX_DELAY = 30

        attr_reader :url, :last_error, :notification_queue

        def initialize(url:)
          base_uri = URI.parse(url)
          base_path = base_uri.path
          base_path += '/' unless base_path.end_with?('/')
          @base_uri = base_uri.dup
          @base_uri.path = base_path

          @sse_uri = @base_uri + 'sse'
          @message_uri = @base_uri + 'messages'
          @sse_reader_thread = nil
          @connected = false
          @disconnecting = false
          @request_id_counter = 0
          @notification_queue = Queue.new
          @connect_signal = nil
          @last_error = nil
          Legate.logger.info("SSE Connection initialized for URL: #{@base_uri}, SSE: #{@sse_uri}, Msg: #{@message_uri}")
        end

        def connected?
          @connected && @sse_reader_thread&.alive?
        end

        # Connects to the SSE endpoint and starts listening for notifications.
        # Initial connection is synchronous — raises on failure.
        # After a successful connection, stream drops trigger automatic reconnection.
        # @raise [ConnectionError] if the initial connection fails.
        def connect
          return true if connected?

          Legate.logger.info("Connecting to SSE endpoint: #{@sse_uri}...")
          @disconnecting = false
          @last_error = nil
          @notification_queue.clear
          @connect_signal = Queue.new

          @sse_reader_thread = Thread.new { connection_loop }

          result = @connect_signal.pop(timeout: 10)
          @connect_signal = nil

          raise ConnectionError, @last_error || 'Failed to establish SSE connection within timeout' unless result == :connected

          true
        end

        # Disconnects the SSE stream and stops reconnection attempts.
        def disconnect
          return unless @connected || @sse_reader_thread

          Legate.logger.info('Disconnecting SSE connection...')
          @disconnecting = true
          @connected = false

          if @sse_reader_thread&.alive?
            @sse_reader_thread.kill
            @sse_reader_thread.join(2)
          end

          @sse_reader_thread = nil
          @notification_queue.clear
          Legate.logger.info('SSE connection disconnected.')
        end

        # Sends a request via HTTP POST and returns the response immediately.
        # @param json_rpc_hash [Hash] The JSON-RPC request.
        # @return [Hash] The parsed JSON-RPC response from the server.
        def send_request(json_rpc_hash)
          request_json = json_rpc_hash.to_json
          Legate.logger.debug("-> [MCP Client POST] #{@message_uri} Body: #{request_json}")

          begin
            http = Net::HTTP.new(@message_uri.hostname, @message_uri.port)
            http.use_ssl = (@message_uri.scheme == 'https')
            http.open_timeout = 5
            http.read_timeout = 15

            request = Net::HTTP::Post.new(@message_uri.request_uri)
            request['Content-Type'] = 'application/json'
            request['Accept'] = 'application/json'
            request.body = request_json

            response = http.request(request)

            unless response.is_a?(Net::HTTPOK)
              msg = "MCP POST request failed: #{response.code} #{response.message}. Body: #{response.body[0..500]}"
              Legate.logger.error(msg)
              @last_error = msg
              begin
                error_details = JSON.parse(response.body, symbolize_names: true)
                if error_details[:error]
                  raise RemoteToolError.new(error_details[:error][:message], error_details[:error][:code],
                                            error_details[:error][:data])
                end
              rescue JSON::ParserError
                # Body is not JSON
              end
              raise ConnectionError, msg
            end

            begin
              response_hash = JSON.parse(response.body, symbolize_names: true)
              Legate.logger.debug("<- [MCP Client POST Response] #{response_hash.inspect}")
              response_hash
            rescue JSON::ParserError => e
              msg = "Failed to parse MCP JSON response from POST: #{e.message}. Body: #{response.body[0..500]}"
              Legate.logger.error(msg)
              @last_error = msg
              raise ProtocolError, msg
            end
          rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
            @last_error = "Failed to send POST to #{@message_uri}: #{e.class} - #{e.message}"
            Legate.logger.error(@last_error)
            raise ConnectionError, @last_error
          rescue Legate::Mcp::ProtocolError, Legate::Mcp::RemoteToolError
            raise
          rescue StandardError => e
            @last_error = "Unexpected error during POST send_request: #{e.class} - #{e.message}"
            Legate.logger.error("#{@last_error}\n#{e.backtrace.join("\n")}")
            raise ConnectionError, @last_error
          end
        end

        # Reads the next notification from the queue.
        # @param timeout [Numeric, nil] Seconds to wait, 0 for non-blocking.
        # @return [Hash, nil] Notification hash or nil if queue is empty/timeout occurs.
        def read_notification(timeout = 0.1)
          return nil unless connected?

          begin
            return @notification_queue.pop(true) if timeout == 0

            @notification_queue.pop(timeout: timeout)
          rescue ThreadError
            nil
          end
        end

        def next_request_id
          @request_id_counter += 1
        end

        private

        def connection_loop
          attempt = 0
          initial = true

          until @disconnecting
            begin
              attempt += 1
              run_sse_stream
              break if @disconnecting

              @connected = false
              initial = false
              attempt = 0
              Legate.logger.info('SSE stream ended, will reconnect.')
            # IOError covers EOFError, and Timeout::Error covers Net::Open/ReadTimeout,
            # so the subclasses are omitted here to avoid shadowed (redundant) rescues.
            rescue ConnectionError, IOError, Errno::ECONNREFUSED,
                   Errno::ECONNRESET, Errno::EHOSTUNREACH, SocketError,
                   Timeout::Error => e
              break if @disconnecting

              @connected = false
              @last_error = e.message

              if initial
                signal_connect(:failed)
                return
              end

              if attempt > MAX_RECONNECT_ATTEMPTS
                Legate.logger.error("SSE: Max reconnect attempts (#{MAX_RECONNECT_ATTEMPTS}) reached: #{e.message}")
                break
              end

              delay = [RECONNECT_BASE_DELAY * (2**(attempt - 1)), RECONNECT_MAX_DELAY].min
              Legate.logger.warn("SSE reconnect #{attempt}/#{MAX_RECONNECT_ATTEMPTS} (#{e.class}). Retrying in #{delay}s...")
              sleep(delay)
            rescue StandardError => e
              @connected = false
              @last_error = "Unexpected SSE error: #{e.class} - #{e.message}"
              Legate.logger.error("#{@last_error}\n#{e.backtrace&.first(5)&.join("\n")}")
              signal_connect(:failed) if initial
              break
            end
          end

          @connected = false
        end

        def run_sse_stream
          Net::HTTP.start(@sse_uri.hostname, @sse_uri.port,
                          use_ssl: @sse_uri.scheme == 'https',
                          open_timeout: 5, read_timeout: 30) do |http|
            request = Net::HTTP::Get.new(@sse_uri.request_uri)
            request['Accept'] = 'text/event-stream'
            request['Cache-Control'] = 'no-cache'

            http.request(request) do |response|
              unless response.is_a?(Net::HTTPOK) && response['content-type']&.include?('text/event-stream')
                raise ConnectionError,
                      "SSE endpoint returned #{response.code}: #{response['content-type']}"
              end

              Legate.logger.info("SSE connection established with #{@sse_uri}.")
              @connected = true
              signal_connect(:connected)

              buffer = +''
              response.read_body do |chunk|
                buffer << chunk
                while (line_end = buffer.index("\n\n"))
                  event_data = buffer.slice!(0, line_end + 2)
                  process_sse_event(event_data)
                end
              end
              Legate.logger.info('SSE stream ended.')
            end
          end
        rescue EOFError
          Legate.logger.info('SSE stream closed by server.')
        end

        def signal_connect(status)
          @connect_signal&.push(status)
          @connect_signal = nil
        end

        def process_sse_event(event_string)
          Legate.logger.debug("Processing SSE Event: #{event_string.inspect}")
          data_buffer = +''
          event_type = nil

          event_string.each_line do |line|
            line.chomp!
            next if line.empty?
            next if line.start_with?(':')

            field, value = line.split(':', 2)
            value&.strip!

            case field
            when 'event'
              event_type = value
            when 'data'
              data_buffer << value << "\n"
            when 'retry'
              Legate.logger.debug("Received SSE retry suggestion: #{value}ms")
            else
              Legate.logger.warn("Ignoring unknown SSE field: #{field}")
            end
          end

          return if data_buffer.empty?

          begin
            message = JSON.parse(data_buffer, symbolize_names: true)
            Legate.logger.debug("Parsed SSE notification (event: #{event_type || 'message'}): #{message.inspect}")
            @notification_queue << message
          rescue JSON::ParserError => e
            Legate.logger.error("Failed to parse JSON from SSE data: #{e.message}. Data: #{data_buffer.inspect}")
          end
        end
      end
    end
  end
end
