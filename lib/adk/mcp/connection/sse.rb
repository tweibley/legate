# File: lib/adk/mcp/connection/sse.rb
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'thread'
require 'timeout'
require_relative '../error'

module ADK
  module Mcp
    module Connection
      # Manages a connection to an MCP server via HTTP/SSE.
      # Uses Server-Sent Events (SSE) for server-to-client notifications
      # and standard HTTP POST for client-to-server requests/responses.
      class Sse
        # TODO: Define timeouts
        # READ_TIMEOUT = 15
        # CONNECT_TIMEOUT = 10

        attr_reader :url, :last_error, :notification_queue

        # @param url [String] Base URL of the MCP server (e.g., "http://localhost:9292/mcp")
        def initialize(url:)
          base_uri = URI.parse(url)
          # Ensure base path ends with a slash for correct joining
          base_path = base_uri.path
          base_path += '/' unless base_path.end_with?('/')
          # Reconstruct base URI with normalized path
          @base_uri = base_uri.dup
          @base_uri.path = base_path

          @sse_uri = @base_uri + 'sse' # Now joins correctly
          @message_uri = @base_uri + 'messages' # Now joins correctly
          @http_client = nil # Net::HTTP instance
          @sse_reader_thread = nil
          @connected = false
          @request_id_counter = 0
          @notification_queue = Queue.new
          @last_error = nil
          ADK.logger.info("SSE Connection initialized for URL: #{@base_uri}, SSE: #{@sse_uri}, Msg: #{@message_uri}")
        end

        def connected?
          @connected && @sse_reader_thread&.alive?
        end

        # Connects to the SSE endpoint and starts listening for notifications.
        # @raise [ConnectionError] if the connection fails.
        def connect
          return true if connected?

          ADK.logger.info("Connecting to SSE endpoint: #{@sse_uri}...")
          @last_error = nil
          @notification_queue.clear

          begin
            @http_client = Net::HTTP.start(@sse_uri.hostname, @sse_uri.port,
                                           use_ssl: @sse_uri.scheme == 'https') do |http|
              # Prepare the GET request for SSE stream
              request = Net::HTTP::Get.new(@sse_uri.request_uri)
              request['Accept'] = 'text/event-stream'
              request['Cache-Control'] = 'no-cache'
              ADK.logger.debug("Sending SSE connection request to #{@sse_uri}")

              # Start the request and process the response stream
              http.request(request) do |response|
                unless response.is_a?(Net::HTTPOK) && response['content-type']&.include?('text/event-stream')
                  msg = "Failed to establish SSE connection. Status: #{response.code}, Content-Type: #{response['content-type']}"
                  ADK.logger.error(msg)
                  @last_error = msg
                  raise ConnectionError, msg
                end

                ADK.logger.info("SSE connection established with #{@sse_uri}.")
                @connected = true

                # Start the reader thread *after* confirming connection
                @sse_reader_thread = Thread.new(response) do |resp|
                  begin
                    buffer = ''
                    # Use read_body to stream chunks
                    resp.read_body do |chunk|
                      buffer << chunk
                      while (line_end = buffer.index("\n\n"))
                        event_data = buffer.slice!(0, line_end + 2)
                        process_sse_event(event_data)
                      end
                      # Handle potential partial message at the end if needed
                    end
                    ADK.logger.info('SSE stream ended.')
                  rescue EOFError
                    ADK.logger.info('SSE stream closed by server.')
                  rescue StandardError => e
                    ADK.logger.error("Error reading SSE stream: #{e.class} - #{e.message}")
                    ADK.logger.error(e.backtrace.join("\n"))
                    @last_error = "SSE stream read error: #{e.message}"
                  ensure
                    ADK.logger.debug('SSE reader thread finishing...')
                    @connected = false # Mark as disconnected if thread stops
                  end
                end

                # Keep the outer block alive while the reader thread runs
                @sse_reader_thread.join
              end # http.request block
            end # Net::HTTP.start block
          rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
            @last_error = "Failed to connect to SSE endpoint #{@sse_uri}: #{e.class} - #{e.message}"
            ADK.logger.error(@last_error)
            @connected = false
            raise ConnectionError, @last_error
          rescue StandardError => e
            @last_error = "Unexpected error during SSE connect: #{e.class} - #{e.message}"
            ADK.logger.error("#{@last_error}\n#{e.backtrace.join("\n")}")
            @connected = false
            raise ConnectionError, @last_error
          ensure
            # If something went wrong after Net::HTTP started but before thread join,
            # ensure we mark as disconnected.
            @connected = false unless @sse_reader_thread&.alive?
            ADK.logger.info("SSE connect method finished. Connected: #{connected?}")
          end

          connected? # Return final connection status
        end

        # Disconnects the SSE stream and stops the reader thread.
        def disconnect
          return unless @connected || @sse_reader_thread # Only if connected or thread exists

          ADK.logger.info('Disconnecting SSE connection...')
          @connected = false # Mark as disconnected first

          # Stop the reader thread
          if @sse_reader_thread&.alive?
            ADK.logger.debug('Stopping SSE reader thread...')
            @sse_reader_thread.kill # Forcefully stop the thread
            @sse_reader_thread.join(1) # Wait briefly for it to finish
          end

          # Close the HTTP connection if it's still around (might be handled by thread exit)
          # Net::HTTP might not expose a direct close method easily here, depends on how start was used.
          # Relying on thread termination and marking @connected=false is often sufficient.

          @sse_reader_thread = nil
          @http_client = nil # Let GC handle connection pool if any
          @notification_queue.clear
          ADK.logger.info('SSE connection disconnected.')
        end

        # Sends a request via HTTP POST and returns the response immediately.
        # @param json_rpc_hash [Hash] The JSON-RPC request.
        # @return [Hash] The parsed JSON-RPC response from the server.
        # @raise [ConnectionError] if the HTTP POST fails or returns non-200.
        # @raise [ProtocolError] if the response body is not valid JSON.
        def send_request(json_rpc_hash)
          # Note: This does *not* check @connected state for SSE, as POST is independent.
          # However, a check might be desired depending on application logic.
          request_json = json_rpc_hash.to_json
          ADK.logger.debug("-> [MCP Client POST] #{@message_uri} Body: #{request_json}")

          begin
            http = Net::HTTP.new(@message_uri.hostname, @message_uri.port)
            http.use_ssl = (@message_uri.scheme == 'https')
            # TODO: Add timeouts (open, read)
            # http.open_timeout = CONNECT_TIMEOUT
            # http.read_timeout = READ_TIMEOUT

            request = Net::HTTP::Post.new(@message_uri.request_uri)
            request['Content-Type'] = 'application/json'
            request['Accept'] = 'application/json'
            request.body = request_json

            response = http.request(request)

            unless response.is_a?(Net::HTTPOK)
              msg = "MCP POST request failed: #{response.code} #{response.message}. Body: #{response.body[0..500]}"
              ADK.logger.error(msg)
              @last_error = msg
              # Attempt to parse body for JSON-RPC error details
              begin
                error_details = JSON.parse(response.body, symbolize_names: true)
                if error_details[:error]
                  raise RemoteToolError.new(error_details[:error][:message], error_details[:error][:code],
                                            error_details[:error][:data])
                end
              rescue JSON::ParserError
                # Ignore if body is not JSON
              end
              raise ConnectionError, msg # Raise generic connection error if no specific MCP error found
            end

            # Parse the successful response
            begin
              response_hash = JSON.parse(response.body, symbolize_names: true)
              ADK.logger.debug("<- [MCP Client POST Response] #{response_hash.inspect}")
              return response_hash
            rescue JSON::ParserError => e
              msg = "Failed to parse MCP JSON response from POST: #{e.message}. Body: #{response.body[0..500]}"
              ADK.logger.error(msg)
              @last_error = msg
              raise ProtocolError, msg
            end
          rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
            @last_error = "Failed to send POST to #{@message_uri}: #{e.class} - #{e.message}"
            ADK.logger.error(@last_error)
            raise ConnectionError, @last_error
          rescue ADK::Mcp::ProtocolError, ADK::Mcp::RemoteToolError
            # Allow specific MCP errors to propagate directly
            raise
          rescue StandardError => e
            @last_error = "Unexpected error during POST send_request: #{e.class} - #{e.message}"
            ADK.logger.error("#{@last_error}\n#{e.backtrace.join("\n")}")
            raise ConnectionError, @last_error # Raise other errors as ConnectionError
          end
        end

        # Reads the next notification from the queue.
        # Does not block indefinitely by default.
        # @param timeout [Numeric, nil] Seconds to wait, 0 for non-blocking, nil for default (e.g., 0.1s).
        # @return [Hash, nil] Notification hash or nil if queue is empty/timeout occurs.
        def read_notification(timeout = 0.1)
          # Return nil if not connected
          return nil unless connected?

          begin
            # Non-blocking read
            if timeout == 0
              return @notification_queue.pop(true)
            end

            # Read with timeout
            Timeout.timeout(timeout) do
              return @notification_queue.pop
            end
          rescue ThreadError
            # Queue empty (for non-blocking calls)
            nil
          rescue Timeout::Error
            # Timeout occurred (for blocking calls with timeout)
            nil
          end
        end

        def next_request_id
          @request_id_counter += 1
        end

        private

        # Processes a raw SSE event string.
        # Parses data lines and pushes JSON onto notification queue.
        def process_sse_event(event_string)
          ADK.logger.debug("Processing SSE Event: #{event_string.inspect}")
          data_buffer = +'' # Use unary plus for mutable empty string
          event_type = nil
          # id = nil # Not typically used by MCP notifications

          event_string.each_line do |line|
            line.chomp!
            next if line.empty? # Skip blank lines separating events
            next if line.start_with?(':') # Skip comments

            field, value = line.split(':', 2)
            value.strip! if value

            case field
            when 'event'
              event_type = value
            when 'data'
              data_buffer << value << "\n" # Append data lines
            # when 'id'
            #  id = value
            when 'retry'
              # Optional: handle retry timeout from server
              ADK.logger.debug("Received SSE retry suggestion: #{value}ms")
            else
              ADK.logger.warn("Ignoring unknown SSE field: #{field}")
            end
          end

          # Once the blank line is processed, parse the accumulated data
          unless data_buffer.empty?
            begin
              message = JSON.parse(data_buffer, symbolize_names: true)
              ADK.logger.debug("Parsed SSE notification (event: #{event_type || 'message'}): #{message.inspect}")
              # Assume all messages via SSE are notifications
              @notification_queue << message
            rescue JSON::ParserError => e
              ADK.logger.error("Failed to parse JSON from SSE data: #{e.message}. Data: #{data_buffer.inspect}")
              # Maybe increment a parse error counter here too?
            end
          end
        end
      end
    end
  end
end
