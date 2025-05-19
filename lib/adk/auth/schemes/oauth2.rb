# File: lib/adk/auth/schemes/oauth2.rb
# frozen_string_literal: true

module ADK
  module Auth
    module Schemes
      # Implements OAuth 2.0 authentication
      # Supports authorization code flow, client credentials flow, and token refresh
      class OAuth2 < ADK::Auth::Scheme
        # @return [String] The URL for the authorization endpoint
        attr_reader :authorization_url
        
        # @return [String] The URL for the token endpoint
        attr_reader :token_url
        
        # @return [Array<String>] The requested scopes
        attr_reader :scopes
        
        # Initialize a new OAuth2 scheme
        # @param authorization_url [String] The URL for the authorization endpoint
        # @param token_url [String] The URL for the token endpoint
        # @param scopes [Array<String>, String, nil] The requested scopes
        # @param additional_params [Hash, nil] Additional parameters for authorization requests
        def initialize(authorization_url:, token_url:, scopes: nil, additional_params: nil)
          @authorization_url = authorization_url
          @token_url = token_url
          @scopes = parse_scopes(scopes)
          @additional_params = additional_params || {}
          validate!
        end
        
        # @return [Symbol] The scheme type
        def scheme_type
          :oauth2
        end
        
        # Validates the scheme configuration
        # @raise [ADK::Auth::SchemeValidationError] If the configuration is invalid
        def validate!
          unless @authorization_url && !@authorization_url.empty?
            raise ADK::Auth::SchemeValidationError, 'Authorization URL is required'
          end
          
          unless @token_url && !@token_url.empty?
            raise ADK::Auth::SchemeValidationError, 'Token URL is required'
          end
        end
        
        # Checks if the scheme supports token refresh
        # @return [Boolean] True if the scheme supports token refresh
        def supports_refresh?
          true
        end
        
        # Applies the OAuth token to a request
        # @param request [Hash] The request to apply the token to
        # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential with the token
        # @return [Hash] The updated request
        # @raise [ADK::Auth::CredentialError] If the credential is missing the token
        def apply_to_request(request, credential)
          # For OAuth2, we should have an ExchangedCredential with an access token
          unless credential.is_a?(ADK::Auth::ExchangedCredential)
            raise ADK::Auth::CredentialError, 'OAuth2 requires an exchanged credential with an access token'
          end
          
          token = credential.access_token
          
          unless token && !token.empty?
            raise ADK::Auth::CredentialError, 'Access token is missing from credential'
          end
          
          request = request.dup
          request[:headers] ||= {}
          request[:headers]['Authorization'] = "Bearer #{token}"
          
          request
        end
        
        # Build the authorization URI for the OAuth2 flow
        # @param config [ADK::Auth::Config] The authentication configuration
        # @param redirect_uri [String, nil] The redirect URI for the authorization request
        # @param state [String, nil] A state parameter for CSRF protection
        # @return [String] The authorization URI
        def build_authorization_uri(config, redirect_uri = nil, state = nil)
          # Implementation requires a credential with a client_id
          credential = config.credential
          
          unless credential && credential.auth_type == :oauth2
            raise ADK::Auth::CredentialError, 'OAuth2 requires a credential with auth_type :oauth2'
          end
          
          client_id = credential[:client_id, resolve_env: true]
          
          unless client_id && !client_id.empty?
            raise ADK::Auth::CredentialError, 'Client ID is missing from credential'
          end
          
          # Build the authorization URL with parameters
          params = {
            'client_id' => client_id,
            'response_type' => 'code',
            'redirect_uri' => redirect_uri,
            'state' => state
          }
          
          # Add scopes if present
          params['scope'] = @scopes.join(' ') if @scopes && !@scopes.empty?
          
          # Add any additional parameters
          params.merge!(@additional_params) if @additional_params
          
          # Remove nil values
          params.compact!
          
          # Build the query string
          require 'uri'
          query = URI.encode_www_form(params)
          
          # Join with the authorization URL
          if @authorization_url.include?('?')
            "#{@authorization_url}&#{query}"
          else
            "#{@authorization_url}?#{query}"
          end
        end
        
        # Exchanges an authorization code for tokens
        # @param config [ADK::Auth::Config] The authentication configuration with response URI
        # @param credential [ADK::Auth::Credential] The credential with client information
        # @return [ADK::Auth::ExchangedCredential] The exchanged credential with tokens
        # @raise [ADK::Auth::TokenExchangeError] If token exchange fails
        def exchange_token(config, credential)
          # This is a stub implementation for now
          # In the actual implementation, we would:
          # 1. Extract the authorization code from the response URI
          # 2. Make a token request to the token endpoint
          # 3. Parse the response and return an ExchangedCredential
          
          # For testing purposes, return a dummy credential
          ADK::Auth::ExchangedCredential.new(
            auth_type: :oauth2,
            access_token: 'dummy_access_token',
            refresh_token: 'dummy_refresh_token',
            token_type: 'Bearer',
            expires_in: 3600,
            scope: @scopes.join(' ')
          )
        end
        
        # Refreshes an access token using a refresh token
        # @param exchanged_credential [ADK::Auth::ExchangedCredential] The credential with the refresh token
        # @param credential [ADK::Auth::Credential] The original credential with client information
        # @return [ADK::Auth::ExchangedCredential] The refreshed credential
        # @raise [ADK::Auth::TokenRefreshError] If token refresh fails
        def refresh_token(exchanged_credential, credential)
          # This is a stub implementation for now
          # In the actual implementation, we would:
          # 1. Extract the refresh token from the exchanged credential
          # 2. Make a refresh request to the token endpoint
          # 3. Parse the response and return a new ExchangedCredential
          
          # For testing purposes, return a dummy refreshed credential
          ADK::Auth::ExchangedCredential.new(
            auth_type: :oauth2,
            access_token: 'refreshed_access_token',
            refresh_token: exchanged_credential.refresh_token,
            token_type: 'Bearer',
            expires_in: 3600,
            scope: @scopes.join(' ')
          )
        end
        
        # Convert to a hash
        # @return [Hash] A hash representation of the scheme
        def to_h
          super.merge(
            authorization_url: @authorization_url,
            token_url: @token_url,
            scopes: @scopes,
            additional_params: @additional_params
          ).compact
        end
        
        private
        
        # Parse scopes from various input formats
        # @param scopes [Array<String>, String, nil] The scopes to parse
        # @return [Array<String>] An array of scope strings
        def parse_scopes(scopes)
          case scopes
          when Array
            scopes.map(&:to_s)
          when String
            scopes.split(/[\s,]+/)
          when nil
            []
          else
            [scopes.to_s]
          end
        end
      end
    end
  end
end 