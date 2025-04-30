# File: lib/adk/mcp/error.rb
# frozen_string_literal: true

module ADK
  module Mcp
    # Base class for MCP-specific errors within ADK.
    # NOTE: The main ADK::Mcp::Error hierarchy is defined in lib/adk/errors.rb
    # This file primarily defines errors unique to MCP interactions not covered there,
    # like RemoteToolError, or keeps the base McpError definition if needed.
    class McpError < StandardError; end # Keep base error if needed, or inherit from ADK::Error?

    # Removing redundant definitions below - they should inherit from ADK::Mcp::Error
    # defined in lib/adk/errors.rb
    # class ConnectionError < McpError; end
    # class ProtocolError < McpError; end
    # class SchemaConversionError < McpError; end

    # Error received from the remote MCP server during a tool call.
    class RemoteToolError < McpError # Keep this as it's specialized
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
