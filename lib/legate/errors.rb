# File: lib/legate/errors.rb
# frozen_string_literal: true

# Single authoritative error hierarchy for the Legate framework.
# All Legate error classes are defined here.

module Legate
  # Base error class for all Legate errors.
  class Error < StandardError; end

  # --- Configuration Errors ---

  # Raised when a required configuration is missing or invalid.
  class ConfigurationError < Error; end

  # --- State Errors ---

  # Raised when an invalid prefix is used in state keys.
  class InvalidPrefixError < Error; end

  # Raised when state value cannot be serialized.
  class SerializationError < Error; end

  # --- Tool Errors ---

  # Base class for errors raised during tool execution.
  # Supports wrapping an original cause exception for debugging.
  class ToolError < Error
    # @param message [String] The error message.
    # @param cause [Exception, nil] The original exception that triggered this error.
    def initialize(message = nil, cause: nil)
      super(message)
      @cause = cause
      set_backtrace(cause.backtrace) if cause&.backtrace
    end

    # The explicit wrapped cause if one was passed, otherwise Ruby's implicit
    # cause (set automatically when the error is raised inside a rescue). Falling
    # back to `super` means a caller that does `raise ToolError, msg` inside a
    # rescue still surfaces the real cause instead of nil.
    # @return [Exception, nil] The original exception that caused this error.
    def cause
      @cause || super
    end
  end

  # Raised when tool arguments are invalid (e.g., missing, wrong type).
  class ToolArgumentError < ToolError; end

  # Raised when a tool encounters a network-related issue (connection failures, DNS, SSL errors).
  class ToolNetworkError < ToolError; end

  # Raised when SSL/TLS certificate verification fails during an HTTP request.
  class ToolCertificateError < ToolNetworkError; end

  # Raised when a tool operation times out (connection, read, or write timeout).
  class ToolTimeoutError < ToolError; end

  # Raised when an HTTP request receives an unsuccessful status code (4xx or 5xx).
  class ToolHttpError < ToolError
    # @return [Object, nil] The HTTP response object (provides status, headers, body).
    attr_reader :response

    # @param message [String] The error message.
    # @param response [Object, nil] The HTTP response object.
    # @param cause [Exception, nil] The original exception.
    def initialize(message = nil, response: nil, cause: nil)
      super(message, cause: cause)
      @response = response
    end
  end

  # --- Webhook Errors ---

  # Raised for webhook configuration or processing errors within the listener.
  class WebhookConfigurationError < Error; end

  # --- Storage Errors ---

  # Raised for definition or session storage operation failures.
  class StoreError < Error; end

  # --- Definition Store Errors ---
  module DefinitionStore
    class Error < Legate::Error; end
    class StoreError < Error; end
  end

  # --- MCP Errors ---
  module Mcp
    # Base class for MCP-specific errors.
    class Error < Legate::Error; end

    # Raised when an MCP connection cannot be established.
    class ConnectionError < Error; end

    # Raised for MCP protocol violations or JSON-RPC formatting errors.
    class ProtocolError < Error; end

    # Error received from a remote MCP server during a tool call.
    class RemoteToolError < Error
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
