# File: lib/adk/auth/scheme.rb
# frozen_string_literal: true

module ADK
  module Auth
    # Abstract base class for all authentication schemes.
    # Defines the interface that all authentication schemes must implement.
    #
    # Authentication schemes define how an API expects credentials to be provided
    # and processed. Concrete implementations include APIKey, HTTPBearer, OAuth2, etc.
    #
    # @abstract Subclass and override the required methods to implement a new authentication scheme
    class Scheme
      # Returns the unique identifier for this type of authentication scheme
      # @return [Symbol] The scheme identifier
      # @abstract
      def scheme_type
        raise NotImplementedError, 'Subclasses must implement scheme_type'
      end

      # Validates the scheme configuration
      # @raise [ADK::Auth::SchemeValidationError] If the scheme configuration is invalid
      # @abstract
      def validate!
        raise NotImplementedError, 'Subclasses must implement validate!'
      end

      # Returns a hash representation of the scheme
      # @return [Hash] A hash containing the scheme configuration
      # @abstract
      def to_h
        { type: scheme_type }
      end

      # Returns a string representation of the scheme
      # @return [String] A string representing the scheme
      def to_s
        "#{self.class.name}<#{scheme_type}>"
      end

      # Builds an authorization URI for interactive authentication flows
      # @param config [ADK::Auth::Config] The authentication configuration
      # @param redirect_uri [String, nil] The redirect URI for the authorization request
      # @param state [String, nil] A state parameter for the authorization request
      # @return [String, nil] The authorization URI, or nil if not applicable
      # @abstract
      def build_authorization_uri(config, redirect_uri = nil, state = nil)
        nil # No-op in base class, override in subclasses that support interactive flows
      end

      # Applies the authentication to a request
      # @param request [Hash] The request to apply authentication to
      # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential to use
      # @return [Hash] The updated request with authentication applied
      # @abstract
      def apply_to_request(request, credential)
        raise NotImplementedError, 'Subclasses must implement apply_to_request'
      end

      # Checks if the scheme supports token refresh
      # @return [Boolean] True if the scheme supports token refresh, false otherwise
      def supports_refresh?
        false # Default to false, override in subclasses that support refresh
      end

      # Performs token refresh using the provided refresh token
      # @param exchanged_credential [ADK::Auth::ExchangedCredential] The credential containing the refresh token
      # @param credential [ADK::Auth::Credential] The original credential with client information
      # @return [ADK::Auth::ExchangedCredential] The refreshed credential
      # @raise [ADK::Auth::TokenRefreshError] If token refresh fails
      # @abstract
      def refresh_token(exchanged_credential, credential)
        raise ADK::Auth::TokenRefreshError, 'This scheme does not support token refresh'
      end

      # Exchanges a code or other temporary credential for a token
      # @param config [ADK::Auth::Config] The authentication configuration with response
      # @param credential [ADK::Auth::Credential] The credential with client information
      # @return [ADK::Auth::ExchangedCredential] The exchanged credential
      # @raise [ADK::Auth::TokenExchangeError] If token exchange fails
      # @abstract
      def exchange_token(config, credential)
        raise ADK::Auth::TokenExchangeError, 'This scheme does not support token exchange'
      end

      # Checks if a response indicates an authentication error
      # @param response [Hash] The HTTP response to check
      # @return [Boolean] True if the response indicates an authentication error
      def authentication_error?(response)
        return false unless response.is_a?(Hash)
        
        # HTTP status codes for auth errors (401 Unauthorized, 403 Forbidden)
        [401, 403].include?(response[:status])
      end
    end
  end
end 