# File: lib/adk/errors.rb
# frozen_string_literal: true

module ADK
  # Base error class for all ADK errors
  class Error < StandardError; end

  # --- Core Configuration & Runtime Errors ---

  # Raised when a required configuration is missing or invalid
  class ConfigurationError < Error; end

  # Raised when a background job operation fails
  class JobError < Error; end

  # Raised when a session operation fails
  class SessionError < Error; end

  # Raised when an operation times out
  class TimeoutError < Error; end

  # Raised when a required dependency is missing
  class DependencyError < Error; end

  # --- State Management Errors ---

  # Raised when state validation fails
  class StateValidationError < Error; end

  # Raised when an invalid prefix is used in state keys
  class InvalidPrefixError < Error; end

  # Raised when state value cannot be serialized
  class SerializationError < Error; end

  # Raised when attempting to modify state directly
  class StateAccessError < Error; end

  # --- Tool Errors ---

  # Base error class for all Tool-related exceptions within the ADK framework.
  # Provides a consistent way to handle errors originating from tool executions.
  # Inherits from ADK::Error to fit within the broader ADK error hierarchy.
  class ToolError < Error
    # Stores the original exception that caused this ToolError, if any.
    # This is useful for debugging lower-level issues (e.g., network errors, library-specific exceptions).
    attr_reader :cause

    # Initializes a new ToolError.
    #
    # @param message [String] The error message.
    # @param cause [Exception, nil] The original exception that triggered this error (optional).
    def initialize(message = nil, cause: nil)
      super(message)
      @cause = cause
      set_backtrace(cause.backtrace) if cause&.backtrace
    end
  end

  # Raised specifically when tool arguments are invalid (e.g., missing, wrong type).
  # Inherits from {ADK::ToolError}.
  # Raise this when input parameters fail validation within the tool's logic.
  class ToolArgumentError < ToolError; end

  # Error raised when a required tool is not found.
  class ToolNotFound < Error; end

  # Error raised when a tool encounters a network-related issue during execution,
  # such as connection failures, DNS resolution problems, or SSL/TLS certificate errors
  # that are not specifically timeout or HTTP status errors.
  class ToolNetworkError < ToolError; end

  # Error raised specifically when an SSL/TLS certificate verification fails during an HTTP request.
  # Inherits from ToolNetworkError as it's a specific type of network problem.
  class ToolCertificateError < ToolNetworkError; end

  # Error raised when a tool operation times out, typically during network requests
  # (e.g., connection timeout, read timeout, write timeout).
  class ToolTimeoutError < ToolError; end

  # Error raised when an HTTP request made by a tool receives an unsuccessful
  # status code (typically 4xx or 5xx).
  class ToolHttpError < ToolError
    # @return [Excon::Response, nil] The response object associated with the HTTP error, if available.
    #   Provides access to status code, headers, and body for detailed error analysis.
    #   Note: This assumes the underlying client provides a response object compatible with this structure.
    attr_reader :response

    # Initializes a new ToolHttpError.
    #
    # @param message [String] The error message.
    # @param response [Excon::Response, Object, nil] The response object from the HTTP client (optional).
    # @param cause [Exception, nil] The original exception (optional).
    def initialize(message = nil, response: nil, cause: nil)
      super(message, cause: cause)
      @response = response
    end
  end

  # Legacy aliases for backward compatibility
  ToolExecutionError = ToolError
  InvalidParametersError = ToolArgumentError

  # --- Agent Errors ---

  # Error raised during planning phase.
  class PlanningError < Error; end

  # --- Webhook Errors ---

  # Error raised when a webhook configuration is invalid.
  class WebhookConfigurationError < Error; end

  # --- Store Errors ---

  # Base error for definition or session storage operations.
  class StoreError < Error; end

  module DefinitionStore
    # Base error for definition store
    class Error < ADK::Error; end

    # Configuration error specific to definition store
    class ConfigurationError < Error; end

    # Store operation error
    # Inherit from ADK::StoreError to allow catching all store errors
    class StoreError < ADK::StoreError; end

    # Definition not found error
    class DefinitionNotFound < StoreError; end
  end

  # --- MCP Errors ---

  module Mcp
    class Error < ADK::Error; end
    class ConnectionError < Error; end
    class HandshakeError < Error; end
    class ToolRegistrationError < Error; end
    class AgentWrapError < Error; end
    # Error related to MCP protocol rules or JSON-RPC formatting.
    class ProtocolError < Error; end
  end

  # Error related to Multi-Capability Protocol (MCP) interactions.
  class McpError < Error; end
  class McpConnectionError < McpError; end
  class McpProtocolError < McpError; end
  class McpTimeoutError < McpError; end
end
