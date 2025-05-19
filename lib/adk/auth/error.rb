# File: lib/adk/auth/error.rb
# frozen_string_literal: true

module ADK
  module Auth
    # Base class for all authentication-related errors
    class Error < ADK::Error
      # @param message [String] The error message
      # @param cause [Exception, nil] The underlying exception that caused this error
      def initialize(message = nil, cause = nil)
        message = "Authentication error#{": #{message}" if message}"
        super(message)
        set_backtrace(cause.backtrace) if cause && cause.backtrace
      end
    end

    # Raised when authentication configuration is invalid
    class ConfigurationError < Error
      def initialize(message = nil, cause = nil)
        super(message || 'Invalid authentication configuration', cause)
      end
    end

    # Raised when a token exchange operation fails
    class TokenExchangeError < Error
      # @param message [String] The error message
      # @param provider_error [String, nil] Error information from the provider
      # @param cause [Exception, nil] The underlying exception that caused this error
      def initialize(message = nil, provider_error = nil, cause = nil)
        error_message = message || 'Token exchange failed'
        error_message = "#{error_message}: #{provider_error}" if provider_error
        super(error_message, cause)
      end
    end

    # Raised when a token refresh operation fails
    class TokenRefreshError < Error
      # @param message [String] The error message
      # @param provider_error [String, nil] Error information from the provider
      # @param cause [Exception, nil] The underlying exception that caused this error
      def initialize(message = nil, provider_error = nil, cause = nil)
        error_message = message || 'Token refresh failed'
        error_message = "#{error_message}: #{provider_error}" if provider_error
        super(error_message, cause)
      end
    end

    # Raised when a token revocation operation fails
    class TokenRevocationError < Error
      # @param message [String] The error message
      # @param provider_error [String, nil] Error information from the provider
      # @param cause [Exception, nil] The underlying exception that caused this error
      def initialize(message = nil, provider_error = nil, cause = nil)
        error_message = message || 'Token revocation failed'
        error_message = "#{error_message}: #{provider_error}" if provider_error
        super(error_message, cause)
      end
    end

    # Raised when an authentication provider returns an error
    class ProviderError < Error
      # @param message [String] The error message
      # @param provider_error [String, nil] Error information from the provider
      # @param cause [Exception, nil] The underlying exception that caused this error
      def initialize(message = nil, provider_error = nil, cause = nil)
        error_message = message || 'Authentication provider error'
        error_message = "#{error_message}: #{provider_error}" if provider_error
        super(error_message, cause)
      end
    end

    # Raised when credentials are missing or invalid
    class CredentialError < Error
      def initialize(message = nil, cause = nil)
        super(message || 'Invalid or missing credentials', cause)
      end
    end

    # Raised when an environment variable used for credentials is not found
    class EnvironmentVariableNotFoundError < CredentialError
      # @param var_name [String] The name of the environment variable
      def initialize(var_name, cause = nil)
        super("Environment variable not found: #{var_name}", cause)
      end
    end

    # Raised when a scheme validation fails
    class SchemeValidationError < ConfigurationError
      def initialize(message = nil, cause = nil)
        super(message || 'Invalid authentication scheme configuration', cause)
      end
    end
  end
end 