# frozen_string_literal: true

module ADK
  # Base error class for all ADK errors
  class Error < StandardError; end

  # --- Core Errors ---

  # Raised when a required configuration is missing or invalid
  class ConfigurationError < Error; end

  # Raised when a required dependency is missing
  class DependencyError < Error; end

  # Raised when an operation times out (generic)
  class TimeoutError < Error; end

  # --- Job Errors ---
  class JobError < Error; end

  # --- Session and State Errors ---

  # Raised when a session operation fails
  class SessionError < Error; end

  # Raised when state validation fails
  class StateValidationError < Error; end

  # Raised when an invalid prefix is used in state keys
  class InvalidPrefixError < Error; end

  # Raised when state value cannot be serialized
  class SerializationError < Error; end

  # Raised when attempting to modify state directly where prohibited
  class StateAccessError < Error; end

  # --- Tool Errors ---

  # Base error class for all Tool-related exceptions within the ADK framework.
  # Provides a consistent way to handle errors originating from tool executions.
  class ToolError < Error
    # Stores the original exception that caused this ToolError, if any.
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
  # Inherits from ToolError.
  class ToolArgumentError < ToolError; end

  # Raised when a tool execution fails (generic)
  class ToolExecutionError < ToolError; end

  # Raised when tool parameters are invalid (alias or specific use case)
  class InvalidParametersError < ToolError; end

  # Error raised when a required tool is not found.
  class ToolNotFound < Error; end

  # Error raised when a tool encounters a network-related issue during execution.
  class ToolNetworkError < ToolError; end

  # Error raised specifically when an SSL/TLS certificate verification fails.
  class ToolCertificateError < ToolNetworkError; end

  # Error raised when a tool operation times out.
  class ToolTimeoutError < ToolError; end

  # Error raised when an HTTP request made by a tool receives an unsuccessful status code.
  class ToolHttpError < ToolError
    # @return [Object, nil] The response object associated with the HTTP error.
    attr_reader :response

    def initialize(message = nil, response: nil, cause: nil)
      super(message, cause: cause)
      @response = response
    end
  end

  # --- Planning Errors ---
  class PlanningError < Error; end

  # --- MCP Errors ---
  module Mcp
    class Error < ADK::Error; end
    class ConnectionError < Error; end
    class HandshakeError < Error; end
    class ToolRegistrationError < Error; end
    class AgentWrapError < Error; end
    class ProtocolError < Error; end
    class TimeoutError < Error; end
  end

  # Legacy/Root MCP Errors (kept for compatibility)
  class McpError < Error; end
  class McpConnectionError < McpError; end
  class McpProtocolError < McpError; end
  class McpTimeoutError < McpError; end

  # --- Webhook Errors ---
  class WebhookConfigurationError < Error; end

  # --- Definition Store Errors ---
  class StoreError < Error; end

  module DefinitionStore
    class Error < ADK::Error; end
    class ConfigurationError < Error; end
    class StoreError < Error; end
    class DefinitionNotFound < StoreError; end
  end
end
