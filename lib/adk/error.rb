# File: lib/adk/error.rb
# frozen_string_literal: true

module ADK
  # Base error class for all ADK errors
  class Error < StandardError; end

  # Raised when a required configuration is missing or invalid
  class ConfigurationError < Error; end

  # Raised when a tool execution fails
  class ToolExecutionError < Error; end

  # Raised when a tool's parameters are invalid
  class InvalidParametersError < Error; end

  # Raised when a background job operation fails
  class JobError < Error; end

  # Raised when a session operation fails
  class SessionError < Error; end

  # Raised when an operation times out
  class TimeoutError < Error; end

  # Raised when a required dependency is missing
  class DependencyError < Error; end
end
