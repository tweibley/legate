# frozen_string_literal: true

require_relative '../coordinator'
require_relative '../schemes/oidc'
require_relative 'oauth2_coordinator'

module ADK
  module Auth
    module Coordinators
      # OIDCCoordinator handles the interactive OpenID Connect authentication flow using fibers.
      # It extends the OAuth2Coordinator with OIDC-specific functionality.
      class OIDCCoordinator < OAuth2Coordinator
        # Initialize a new OIDC coordinator
        # @param scheme [ADK::Auth::Schemes::OIDC] The OIDC scheme
        # @param credential [ADK::Auth::Credential] The credential with client information
        # @param session_service [ADK::SessionService::Base] The session service
        # @param token_store [ADK::Auth::TokenStore, nil] Optional token store
        # @param timeout [Integer, nil] Optional timeout in seconds
        # @param redirect_uri [String, nil] Optional redirect URI
        def initialize(scheme:, credential:, session_service:, token_store: nil, timeout: DEFAULT_TIMEOUT, redirect_uri: nil)
          super
          
          unless scheme.is_a?(ADK::Auth::Schemes::OIDC)
            raise ArgumentError, "Expected an OIDC scheme, got #{scheme.class}"
          end
          
          unless credential.auth_type == :oidc
            # Allow OAuth2 credentials as they are compatible
            unless credential.auth_type == :oauth2
              raise ArgumentError, "Credential must have auth_type :oidc or :oauth2, got #{credential.auth_type}"
            end
          end
        end

        protected

        # Implement the OIDC authentication flow, extending the OAuth2 flow
        # @return [ADK::Auth::ExchangedCredential] The authenticated credential
        # @raise [ADK::Auth::Error] If authentication fails
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
        # @param token [ADK::Auth::ExchangedCredential] The token with access_token
        # @return [ADK::Auth::ExchangedCredential] The token with added userinfo
        # @raise [ADK::Auth::Error] If userinfo fetch fails
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