# File: lib/adk/auth/scheme.rb
# frozen_string_literal: true

module ADK
  module Auth
    # Base class for all authentication schemes.
    # Schemes provide logic for applying authentication to requests,
    # refreshing tokens, and other operations specific to their authentication type.
    class Scheme
      # Get the type of authentication scheme
      # @return [Symbol] The scheme type identifier
      def scheme_type
        raise NotImplementedError, "#{self.class} must implement #scheme_type"
      end
      
      # Apply authentication to a request
      # @param request [Hash] The request hash to modify
      # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential to use
      # @return [Hash] The modified request with authentication applied
      def apply_to_request(request, credential)
        raise NotImplementedError, "#{self.class} must implement #apply_to_request"
      end
      
      # Check if this scheme supports token refresh
      # @return [Boolean] True if this scheme supports token refresh
      def supports_refresh?
        false
      end
      
      # Refresh an authentication token
      # @param token [ADK::Auth::ExchangedCredential] The token to refresh
      # @param credential [ADK::Auth::Credential] The credential containing refresh parameters
      # @return [ADK::Auth::ExchangedCredential] The refreshed token
      # @raise [ADK::Auth::TokenRefreshError] If the token cannot be refreshed
      def refresh_token(token, credential)
        raise NotImplementedError, "#{self.class} does not support token refresh"
      end
      
      # Exchange a credential for a token
      # @param credential [ADK::Auth::Credential] The credential to exchange
      # @return [ADK::Auth::ExchangedCredential] The exchanged token
      # @raise [ADK::Auth::TokenExchangeError] If the credential cannot be exchanged
      def exchange_token(credential)
        raise NotImplementedError, "#{self.class} does not support token exchange"
      end
      
      # Revoke a token
      # @param token [ADK::Auth::ExchangedCredential] The token to revoke
      # @param credential [ADK::Auth::Credential] The credential for revocation parameters
      # @return [Boolean] True if the token was revoked successfully
      # @raise [ADK::Auth::TokenRevokeError] If the token cannot be revoked
      def revoke_token(token, credential)
        raise NotImplementedError, "#{self.class} does not support token revocation"
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