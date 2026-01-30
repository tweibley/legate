# File: lib/adk/errors.rb
# frozen_string_literal: true

module ADK
  class Error < StandardError; end

  # Raised when a security violation is detected
  class SecurityError < Error; end

  # Raised when state validation fails
  class StateValidationError < Error; end

  # Raised when an invalid prefix is used in state keys
  class InvalidPrefixError < Error; end

  # Raised when state value cannot be serialized
  class SerializationError < Error; end

  # Raised when attempting to modify state directly
  class StateAccessError < Error; end

  # --- Tool Errors ---

  # Base class for errors raised during tool execution.
  # Tools should raise this or a more specific subclass (like ToolArgumentError)
  # instead of returning { status: :error, ... }.
  # The agent runtime catches these errors and formats a standard error event.
  # @see ADK::ToolArgumentError
  class ToolError < Error
    # Add attributes here if needed later (e.g., tool name, params)
  end

  # Raised specifically when tool arguments are invalid (e.g., missing, wrong type).
  # Inherits from {ADK::ToolError}.
  # Raise this when input parameters fail validation within the tool's logic.
  class ToolArgumentError < ToolError; end

  # --- Agent and Session Errors ---
  # Placeholder for potential future errors related to agent lifecycle or session management

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

  # --- Definition Store Errors ---
  module DefinitionStore
    class Error < ADK::Error; end
    class ConfigurationError < Error; end
    class StoreError < Error; end
  end

  # Error raised when a required tool is not found.
  class ToolNotFound < Error; end

  # Error raised during tool execution.
  class ToolError < Error; end

  # Error raised during planning phase.
  class PlanningError < Error; end

  # Error related to session management.
  class SessionError < Error; end

  # Error related to Multi-Capability Protocol (MCP) interactions.
  class McpError < Error; end
  class McpConnectionError < McpError; end
  class McpProtocolError < McpError; end
  class McpTimeoutError < McpError; end

  # Error related to webhook configuration or processing within the listener.
  class WebhookConfigurationError < Error; end

  # Define DefinitionStore specific errors (nested or separate?)
  module DefinitionStore
    class DefinitionNotFound < StoreError; end
  end

  # Error related to definition or session storage operations.
  class StoreError < Error; end
end
