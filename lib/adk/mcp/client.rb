# File: lib/adk/mcp/client.rb
# frozen_string_literal: true

require 'json'
require_relative 'connection/stdio'
require_relative 'connection/sse'
require_relative 'error'

module ADK
  module Mcp
    # Client for interacting with an MCP server.
    # Currently supports STDIO connections.
    class Client
      # Default timeout for waiting for a response to a request
      DEFAULT_RESPONSE_TIMEOUT = 15 # seconds

      # Use the constant defined in the Connection module
      PROCESS_START_TIMEOUT = Connection::Stdio::PROCESS_START_TIMEOUT

      attr_reader :connection_params, :server_capabilities, :last_error

      # @param connection_params [Hash] Options for the connection.
      #   For :stdio type: { type: :stdio, command: 'cmd', args: ['arg1'] }
      #   For :sse type:   { type: :sse, url: 'http://...' }
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

      # Establishes the connection and performs the MCP initialize handshake.
      # @raise [ConnectionError] if connection or handshake fails.
      def connect
        return true if connected?

        @lock.synchronize do
          return true if @connected # Double check inside lock

          Mcp.logger.info("MCP Client connecting...")
          @last_error = nil
          begin
            # Instantiate the connection based on type
            case @connection_params[:type]
            when :stdio
              @connection = Connection::Stdio.new(
                command: @connection_params[:command],
                args: @connection_params[:args] || []
              )
            when :sse
              require_relative 'connection/sse' # Ensure SSE connection is loaded
              @connection = Connection::Sse.new(url: @connection_params[:url])
            else
              # This shouldn't be reachable due to initialize check, but belt-and-suspenders
              raise ConnectionError, "Cannot connect: Unsupported connection type: #{@connection_params[:type]}"
            end

            # Establish the low-level connection
            @connection.connect

            # Perform MCP Initialize Handshake
            Mcp.logger.info("Performing MCP initialize handshake...")
            id = @connection.next_request_id
            request = {
              jsonrpc: '2.0',
              id: id,
              method: 'initialize',
              params: {
                # TODO: Define client capabilities ADK supports
                capabilities: {}
              }
            }

            response = send_request_and_wait(request, timeout: PROCESS_START_TIMEOUT)

            unless response && response[:result]
              @last_error = "MCP Initialize failed: No response or missing result. #{response ? "Resp: #{response.inspect}" : 'Connection likely closed.'}"
              raise ConnectionError, @last_error
            end

            @server_capabilities = response[:result][:capabilities] || {}
            Mcp.logger.info("MCP Handshake successful. Server capabilities: #{@server_capabilities.inspect}")

            @connected = true
            Mcp.logger.info("MCP Client connected successfully.")
          rescue ConnectionError => e
            Mcp.logger.error("MCP Client connection failed: #{e.message}")
            disconnect # Ensure cleanup
            raise # Re-raise the connection error
          rescue StandardError => e
            @last_error = "MCP Client unexpected error during connect: #{e.class} - #{e.message}"
            Mcp.logger.error("#{@last_error}\n#{e.backtrace.join("\n")}")
            disconnect # Ensure cleanup
            raise ConnectionError, @last_error # Raise as ConnectionError
          end
        end
        true
      end

      # Disconnects from the MCP server.
      def disconnect
        @lock.synchronize do
          return unless @connected || @connection # Check if there's anything to disconnect

          Mcp.logger.info("MCP Client disconnecting...")
          @connected = false
          @server_capabilities = nil
          @pending_requests.clear

          @connection&.disconnect
          @connection = nil
          Mcp.logger.info("MCP Client disconnected.")
        end
      rescue StandardError => e
        Mcp.logger.error("MCP Client error during disconnect: #{e.message}")
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

        Mcp.logger.debug("Requesting tools list from MCP server...")
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
          Mcp.logger.debug("Received #{tools.count} tools from MCP server.")
          return tools
        elsif response&.key?(:error)
          err = response[:error]
          @last_error = "MCP tools/list failed: #{err[:message]} (Code: #{err[:code]})"
          Mcp.logger.error(@last_error)
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

        Mcp.logger.debug("Calling MCP tool '#{name}' with args: #{arguments.inspect}")
        id = @connection.next_request_id
        request = {
          jsonrpc: '2.0',
          id: id,
          method: 'tools/call',
          params: { name: name, arguments: arguments }
        }

        response = send_request_and_wait(request)

        if response&.key?(:result)
          Mcp.logger.debug("MCP tool '#{name}' call successful. Result: #{response[:result].inspect}")
          return response[:result]
        elsif response&.key?(:error)
          err = response[:error]
          @last_error = "MCP tool '#{name}' call failed: #{err[:message]} (Code: #{err[:code]})"
          Mcp.logger.error("#{@last_error} Data: #{err[:data].inspect}")
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
          ADK.logger.debug("Connection type #{@connection_params[:type]} does not support read_notification.")
          nil
        end
      end

      private

      # Helper to send a request and wait for the specific response by ID.
      # This simplifies the request/response handling compared to raw read_message.
      # @param request [Hash] The JSON-RPC request hash with an ID.
      # @param timeout [Numeric] Seconds to wait for the response.
      # @return [Hash, nil] The parsed JSON-RPC response hash, or nil if timeout occurs.
      # @raise [ConnectionError] if connection lost during wait.
      def send_request_and_wait(request, timeout: DEFAULT_RESPONSE_TIMEOUT)
        raise ConnectionError, 'Not connected' unless connected?
        raise ArgumentError, 'Request must have an ID' unless request[:id]

        # --- Handle response differently based on connection type ---
        if @connection.is_a?(Connection::Sse)
          # SSE connection returns response directly from send_request (HTTP POST response)
          ADK.logger.debug("Sending request via SSE POST and expecting immediate response...")
          response = @connection.send_request(request)
          # Response already contains the result or error hash
          ADK.logger.debug("Received direct response for SSE request ID #{request[:id]}")
          return response
        elsif @connection.is_a?(Connection::Stdio)
          # STDIO connection puts response in a queue, need to wait/poll
          request_id = request[:id]
          @connection.send_request(request)
          ADK.logger.debug("Waiting for response to STDIO request ID #{request_id} (timeout: #{timeout}s)")
          # Simple wait loop - checks queue periodically
          # A more robust implementation might use ConditionVariable + timeout
          start_time = Time.now
          loop do
            # Check if the connection died
            raise ConnectionError, "Connection lost while waiting for response ID #{request_id}" unless connected?

            # Check response queue non-blockingly first
            begin
              response = @connection.instance_variable_get(:@response_queue).pop(true)
              if response && response[:id] == request_id
                ADK.logger.debug("Received response for ID #{request_id}")
                return response
              elsif response # Got response for a different ID, put it back (or handle if needed)
                ADK.logger.warn("Received unexpected response ID #{response[:id]} while waiting for #{request_id}")
                @connection.instance_variable_get(:@response_queue).push(response)
              end
            rescue ThreadError
              # Queue was empty, continue loop
            end

            # Check timeout
            if Time.now - start_time > timeout
              @last_error = "MCP Client timeout waiting for response ID #{request_id}"
              ADK.logger.error(@last_error)
              return nil
            end

            # Sleep between checks
            sleep(0.01) # 10ms between checks
          end
        else
          # Should not happen if initialize enforces types
          raise ConnectionError, "Unsupported connection type for sending request: #{@connection.class}"
        end
        # -------------------------------------------------------------
      end
    end
  end
end
