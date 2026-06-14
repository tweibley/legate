# frozen_string_literal: true

require_relative '../coordinator'
require_relative '../schemes/openid_connect'
require_relative 'oauth2_coordinator'

module Legate
  module Auth
    module Coordinators
      # OIDCCoordinator handles the interactive OpenID Connect authentication flow using fibers.
      # It extends the OAuth2Coordinator with OIDC-specific functionality.
      class OIDCCoordinator < OAuth2Coordinator
        # Initialize a new OIDC coordinator
        # @param scheme [Legate::Auth::Schemes::OpenIDConnect] The OIDC scheme
        # @param credential [Legate::Auth::Credential] The credential with client information
        # @param session_service [Legate::SessionService::Base] The session service
        # @param token_store [Legate::Auth::TokenStore, nil] Optional token store
        # @param timeout [Integer, nil] Optional timeout in seconds
        # @param redirect_uri [String, nil] Optional redirect URI
        def initialize(scheme:, credential:, session_service:, token_store: nil, timeout: DEFAULT_TIMEOUT, redirect_uri: nil)
          super

          raise ArgumentError, "Expected an OIDC scheme, got #{scheme.class}" unless scheme.is_a?(Legate::Auth::Schemes::OIDC)

          return if credential.auth_type == :oidc
          # Allow OAuth2 credentials as they are compatible
          return if credential.auth_type == :oauth2

          raise ArgumentError, "Credential must have auth_type :oidc or :oauth2, got #{credential.auth_type}"
        end

        protected

        # Implement the OIDC authentication flow, extending the OAuth2 flow
        # @return [Legate::Auth::ExchangedCredential] The authenticated credential
        # @raise [Legate::Auth::Error] If authentication fails
        def authenticate
          # Call the parent (OAuth2) authentication flow first
          oauth2_result = super

          # For OIDC, we may want to request the userinfo endpoint
          # if the ID token doesn't have all needed claims
          if @scheme.should_fetch_userinfo? && oauth2_result
            fetch_userinfo(oauth2_result)
          else
            oauth2_result
          end
        end

        private

        # Fetch additional user information using the userinfo endpoint
        # @param token [Legate::Auth::ExchangedCredential] The token with access_token
        # @return [Legate::Auth::ExchangedCredential] The token with added userinfo
        # @raise [Legate::Auth::Error] If userinfo fetch fails
        def fetch_userinfo(token)
          # Fetch userinfo using the access token
          userinfo = @scheme.fetch_userinfo(token)

          # Add the userinfo to the token metadata
          token.with(
            metadata: (token.metadata || {}).merge(userinfo: userinfo)
          )
        end
      end
    end
  end
end
