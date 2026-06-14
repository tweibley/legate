# File: lib/legate/mcp/client.rb
# frozen_string_literal: true

require 'json'
require_relative 'connection/stdio'
require_relative 'connection/sse'
require_relative '../errors'

module Legate
  module Mcp
    class Client
      DEFAULT_RESPONSE_TIMEOUT = 30
      PROCESS_START_TIMEOUT = Connection::Stdio::PROCESS_START_TIMEOUT
      # --- Define the protocol version Legate Client supports ---
      CLIENT_PROTOCOL_VERSION = '2024-11-05'
      # -----------------------------------------------------

      attr_reader :connection_params, :server_capabilities, :last_error

      # ... (initialize remains the same) ...
      def initialize(connection_params)
        @connection_params = connection_params
        @connection = nil
        @server_capabilities = nil
        @connected = false
        @pending_requests = {}
        @lock = Mutex.new
        @last_error = nil

        # Validate connection params based on type
        case @connection_params[:type]
        when :stdio
          raise ArgumentError, 'Missing :command for :stdio connection' unless @connection_params[:command]
        when :sse
          raise ArgumentError, 'Missing :url for :sse connection' unless @connection_params[:url]
        else
          raise ArgumentError, "Unsupported connection type: #{@connection_params[:type]}"
        end
      end

      def connected?
        @connected && @connection&.connected?
      end

      def connect
        return true if connected?

        error_occurred = nil

        @lock.synchronize do
          return true if @connected # Double check

          Legate.logger.info('MCP Client connecting...')
          @last_error = nil
          @connection = nil
          @connected = false

          begin
            case @connection_params[:type]
            when :stdio
              @connection = Connection::Stdio.new(
                command: @connection_params[:command],
                args: @connection_params[:args] || []
              )
            when :sse
              # require_relative 'connection/sse' # Ensure loaded if not globally required
              @connection = Connection::Sse.new(url: @connection_params[:url])
            else
              raise ConnectionError, "Cannot connect: Unsupported connection type: #{@connection_params[:type]}"
            end

            @connection.connect
            @connected = true # Assume connected for handshake

            Legate.logger.info('Performing MCP initialize handshake...')
            id = @connection.next_request_id
            # --- MODIFICATION: Add protocolVersion to params ---
            request = {
              jsonrpc: '2.0', id: id, method: 'initialize',
              params: {
                protocolVersion: CLIENT_PROTOCOL_VERSION,
                clientInfo: { name: 'legate-client', version: Legate::VERSION },
                capabilities: {} # Keep capabilities empty for now
              }
            }
            # --- End Modification ---
            Legate.logger.info("Initialize Request: #{request.inspect}") # Log modified request

            response = send_request_and_wait(request, timeout: PROCESS_START_TIMEOUT)

            unless response && response[:result]
              error_msg = 'MCP Initialize failed: No response or missing result.'
              if response&.dig(:error)
                err = response[:error]
                error_msg += " Server Error: #{err[:message]} (Code: #{err[:code]})"
              elsif !response
                error_msg += ' Connection likely closed or timed out.'
              else
                error_msg += " Response: #{response.inspect}"
              end
              @last_error = error_msg
              raise ConnectionError, @last_error # Raise to be caught below
            end

            # --- Optional: Validate Server Protocol Version ---
            server_protocol_version = response.dig(:result, :protocolVersion)
            if server_protocol_version && server_protocol_version != CLIENT_PROTOCOL_VERSION
              Legate.logger.warn("MCP Protocol version mismatch. Client: #{CLIENT_PROTOCOL_VERSION}, Server: #{server_protocol_version}")
              # Decide if this is a critical error - for now, just log a warning
            end
            # --- End Protocol Version Check ---

            @server_capabilities = response.dig(:result, :capabilities) || {}
            Legate.logger.info("MCP Handshake successful. Server capabilities: #{@server_capabilities.inspect}")
            Legate.logger.info('MCP Client connected successfully.')
          rescue ConnectionError => e
            Legate.logger.error("MCP Client connection/handshake failed: #{e.message}")
            error_occurred = e
            @connected = false
          rescue StandardError => e
            @last_error = "MCP Client unexpected error during connect: #{e.class} - #{e.message}"
            Legate.logger.error("#{@last_error}\n#{e.backtrace.join("\n")}")
            error_occurred = ConnectionError.new(@last_error)
            @connected = false
          end
        end # Lock released

        if error_occurred
          disconnect
          raise error_occurred
        end

        true
      end

      # Disconnects from the MCP server.
      def disconnect
        @lock.synchronize do
          return unless @connected || @connection # Check if there's anything to disconnect

          Legate.logger.info('MCP Client disconnecting...')
          @connected = false
          @server_capabilities = nil
          @pending_requests.clear

          begin
            @connection&.disconnect
          rescue StandardError => e
            Legate.logger.error("MCP Client error during disconnect: #{e.message}")
          end

          @connection = nil
          Legate.logger.info('MCP Client disconnected.')
        end
      ensure
        # Ensure state is updated even if disconnect fails
        @connected = false
        @connection = nil
      end

      # Lists available tools from the MCP server.
      # @return [Array<Hash>] List of MCP tool schemas.
      # @raise [ConnectionError] if not connected.
      # @raise [ProtocolError] if the server response is invalid.
      def list_tools
        raise ConnectionError, 'Not connected' unless connected?

        Legate.logger.debug('Requesting tools list from MCP server...')
        id = @connection.next_request_id
        request = {
          jsonrpc: '2.0',
          id: id,
          method: 'tools/list',
          params: {}
        }

        response = send_request_and_wait(request)

        if response&.key?(:result)
          tools = response.dig(:result, :tools)
          unless tools.is_a?(Array)
            @last_error = "MCP tools/list invalid response: 'result.tools' is not an Array. Response: #{response.inspect}"
            raise ProtocolError, @last_error
          end
          Legate.logger.debug("Received #{tools.count} tools from MCP server.")
          tools
        elsif response&.key?(:error)
          err = response[:error]
          @last_error = "MCP tools/list failed: #{err[:message]} (Code: #{err[:code]})"
          Legate.logger.error(@last_error)
          raise RemoteToolError.new(@last_error, err[:code], err[:data])
        else
          @last_error = "MCP tools/list failed: Invalid or missing response. #{response ? "Resp: #{response.inspect}" : 'Connection likely closed.'}"
          raise ProtocolError, @last_error
        end
      end

      # Calls a tool on the MCP server.
      # @param name [String] The name of the tool to call.
      # @param arguments [Hash] The arguments for the tool.
      # @return [Any] The result payload from the tool execution.
      # @raise [ConnectionError] if not connected.
      # @raise [ProtocolError] if the server response is invalid.
      # @raise [RemoteToolError] if the server returns a tool execution error.
      def call_tool(name, arguments)
        raise ConnectionError, 'Not connected' unless connected?
        raise ArgumentError, 'Arguments must be a Hash' unless arguments.is_a?(Hash)

        Legate.logger.debug("Calling MCP tool '#{name}' with args: #{arguments.inspect}")
        id = @connection.next_request_id
        request = {
          jsonrpc: '2.0',
          id: id,
          method: 'tools/call',
          params: { name: name, arguments: arguments }
        }

        response = send_request_and_wait(request)

        if response&.key?(:result)
          Legate.logger.debug("MCP tool '#{name}' call successful. Result: #{response[:result].inspect}")
          response[:result]
        elsif response&.key?(:error)
          err = response[:error]
          @last_error = "MCP tool '#{name}' call failed: #{err[:message]} (Code: #{err[:code]})"
          Legate.logger.error("#{@last_error} Data: #{err[:data].inspect}")
          raise RemoteToolError.new(err[:message], err[:code], err[:data])
        else
          @last_error = "MCP tool '#{name}' call failed: Invalid or missing response. #{response ? "Resp: #{response.inspect}" : 'Connection likely closed.'}"
          raise ProtocolError, @last_error
        end
      end

      # Reads the next *notification* received from the server via the connection.
      # This is primarily useful for SSE connections.
      # @param timeout [Numeric] Seconds to wait (default 0.1).
      # @return [Hash, nil] Notification hash or nil.
      def read_notification(timeout = 0.1)
        return nil unless connected?

        # Delegate to connection-specific method if it exists, otherwise return nil
        if @connection.respond_to?(:read_notification)
          @connection.read_notification(timeout)
        else
          Legate.logger.debug("Connection type #{@connection_params[:type]} does not support read_notification.")
          nil
        end
      end

      private

      def send_request_and_wait(request, timeout: DEFAULT_RESPONSE_TIMEOUT)
        raise ArgumentError, 'Request must have an ID' unless request[:id]

        request_id = request[:id]
        @pending_requests[request_id] = true # Mark as waiting

        begin
          # Raise connection error immediately if low-level connection is dead
          raise ConnectionError, 'Connection is not alive.' unless @connection&.connected?

          @connection.send_request(request)
          Legate.logger.debug("Sent request ID #{request_id}, waiting for response (timeout: #{timeout}s)")

          start_time = Time.now
          message_buffer = []
          loop do
            # Check if the low-level connection died
            unless @connection&.connected?
              raise ConnectionError,
                    "Connection lost while waiting for response ID #{request_id}"
            end

            # Check buffer first
            message_buffer.reject! do |buffered_message|
              if buffered_message[:id] == request_id
                Legate.logger.debug("Found matching response for ID #{request_id} in buffer")
                return buffered_message
              end
              false # Keep non-matching messages
            end

            # Calculate remaining timeout
            elapsed_time = Time.now - start_time
            remaining_time = timeout - elapsed_time
            if remaining_time <= 0
              @last_error = "MCP Client timeout waiting for response ID #{request_id}"
              Legate.logger.error(@last_error)
              return nil # Timeout occurred
            end

            # Read the next message using the remaining timeout
            Legate.logger.debug("Calling read_message with timeout: #{remaining_time.round(3)}s")
            message = @connection.read_message(remaining_time)

            if message
              Legate.logger.debug("[Client send_request_and_wait] Received message: #{JSON.pretty_generate(message)} while waiting for ID #{request_id}")
              if message[:id] == request_id
                Legate.logger.debug("Received matching response for ID #{request_id}")
                return message
              elsif message[:id]
                Legate.logger.warn("Received unexpected response ID #{message[:id]} while waiting for #{request_id}. Buffering.")
                message_buffer << message
              else
                Legate.logger.debug("Received notification or non-response message while waiting for ID #{request_id}: #{message.inspect}")
              end
            else
              # read_message returned nil, indicating timeout within read_message itself
              @last_error = "MCP Client timeout waiting for response ID #{request_id} (read_message returned nil)"
              Legate.logger.error(@last_error)
              return nil
            end
          end
        ensure
          @pending_requests.delete(request_id) # Clear pending status
        end
      end # --- End send_request_and_wait ---
    end # End Client class
  end # End Mcp module
end # End Legate module
