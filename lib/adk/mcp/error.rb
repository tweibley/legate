# File: lib/adk/mcp/error.rb
# frozen_string_literal: true

module ADK
  module Mcp
    # Base class for MCP-specific errors within ADK.
    class McpError < StandardError; end

    # Error during MCP connection establishment or communication.
    class ConnectionError < McpError; end

    # Error related to MCP protocol rules or JSON-RPC formatting.
    class ProtocolError < McpError; end

    # Error during schema conversion.
    class SchemaConversionError < McpError; end

    # Error received from the remote MCP server during a tool call.
    class RemoteToolError < McpError
      attr_reader :code, :data

      def initialize(message, code = nil, data = nil)
        super(message)
        @code = code
        @data = data
      end

      def to_s
        str = super
        str += " (Code: #{@code})" if @code
        str += " Data: #{@data.inspect}" if @data
        str
      end
    end
  end
end
