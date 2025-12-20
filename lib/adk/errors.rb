# File: lib/adk/errors.rb
# frozen_string_literal: true

module ADK
  class Error < StandardError; end

  # Raised when a required configuration is missing or invalid
  class ConfigurationError < Error; end

  # Raised when state validation fails
  class StateValidationError < Error; end

  # Raised when an invalid prefix is used in state keys
  class InvalidPrefixError < Error; end

  # Raised when state value cannot be serialized
  class SerializationError < Error; end

  # Raised when attempting to modify state directly
  class StateAccessError < Error; end

  # --- Agent and Session Errors ---

  # Error raised during planning phase.
  class PlanningError < Error; end

  # Error related to session management.
  class SessionError < Error; end

  # Error related to definition or session storage operations.
  class StoreError < Error; end

  # Error raised when a required tool is not found.
  class ToolNotFound < Error; end

  # Error related to webhook configuration or processing within the listener.
  class WebhookConfigurationError < Error; end

  # --- Legacy / Potentially Unused Errors (Migrated from error.rb) ---
  # Retained for compatibility.
  class JobError < Error; end
  class DependencyError < Error; end
  class TimeoutError < Error; end
  class ToolExecutionError < Error; end
  class InvalidParametersError < Error; end

  # --- Definition Store Errors ---
  module DefinitionStore
    class Error < ADK::Error; end
    # Maintain compatibility with ADK::DefinitionStore::ConfigurationError
    class ConfigurationError < Error; end
    class StoreError < Error; end
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

# Require tool errors (ToolError, ToolArgumentError, etc.)
# These inherit from ADK::Error defined above.
require_relative 'tool/error'
