# File: lib/legate/auth/scheme.rb
# frozen_string_literal: true

require 'uri'
require_relative 'url_guard'

module Legate
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
      # @param credential [Legate::Auth::Credential, Legate::Auth::ExchangedCredential] The credential to use
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
      # @param token [Legate::Auth::ExchangedCredential] The token to refresh
      # @param credential [Legate::Auth::Credential] The credential containing refresh parameters
      # @return [Legate::Auth::ExchangedCredential] The refreshed token
      # @raise [Legate::Auth::TokenRefreshError] If the token cannot be refreshed
      def refresh_token(token, credential)
        raise NotImplementedError, "#{self.class} does not support token refresh"
      end

      # Exchange a credential for a token
      # @param credential [Legate::Auth::Credential] The credential to exchange
      # @return [Legate::Auth::ExchangedCredential] The exchanged token
      # @raise [Legate::Auth::TokenExchangeError] If the credential cannot be exchanged
      def exchange_token(credential)
        raise NotImplementedError, "#{self.class} does not support token exchange"
      end

      # Revoke a token
      # @param token [Legate::Auth::ExchangedCredential] The token to revoke
      # @param credential [Legate::Auth::Credential] The credential for revocation parameters
      # @return [Boolean] True if the token was revoked successfully
      # @raise [Legate::Auth::TokenRevokeError] If the token cannot be revoked
      def revoke_token(token, credential)
        raise NotImplementedError, "#{self.class} does not support token revocation"
      end

      # Validates the scheme configuration
      # @raise [Legate::Auth::SchemeValidationError] If the scheme configuration is invalid
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
      # @param config [Legate::Auth::Config] The authentication configuration
      # @param redirect_uri [String, nil] The redirect URI for the authorization request
      # @param state [String, nil] A state parameter for the authorization request
      # @return [String, nil] The authorization URI, or nil if not applicable
      # @abstract
      def build_authorization_uri(_config, _redirect_uri = nil, _state = nil)
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

      private

      # Validates that a value is safe to use in an HTTP header.
      # Rejects values containing CR, LF, or null bytes to prevent header injection.
      # @param value [String] The header value to validate
      # @param label [String] A label for error messages (e.g., "Bearer token")
      # @raise [Legate::Auth::Error] If the value contains unsafe characters
      def validate_header_value!(value, label = 'credential')
        return unless value.is_a?(String)

        return unless value.match?(/[\r\n\0]/)

        raise Legate::Auth::Error, "#{label} contains invalid characters (CR, LF, or null byte)"
      end

      # Validates that an auth URL does not point to private/restricted network
      # addresses. Delegates to the canonical {Legate::Auth::UrlGuard} so schemes
      # and the web credential-test routes share one SSRF policy.
      # @param url [String] The URL to validate
      # @param label [String] A label for error messages
      # @raise [Legate::Auth::Error] If the URL resolves to a restricted address
      def validate_auth_url!(url, label: 'Auth URL')
        Legate::Auth::UrlGuard.validate!(url, label: label)
      end
    end
  end
end
