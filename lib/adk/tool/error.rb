# frozen_string_literal: true

module ADK
  # Base error class for all Tool-related exceptions within the ADK framework.
  # Provides a consistent way to handle errors originating from tool executions.
  # Inherits from ADK::Error to fit within the broader ADK error hierarchy.
  class ToolError < ADK::Error
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

  # Error raised when a tool encounters a network-related issue during execution,
  # such as connection failures, DNS resolution problems, or SSL/TLS certificate errors
  # that are not specifically timeout or HTTP status errors.
  class ToolNetworkError < ToolError; end

  # Error raised specifically when an SSL/TLS certificate verification fails during an HTTP request.
  # Inherits from ToolNetworkError as it\'s a specific type of network problem.
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
end
