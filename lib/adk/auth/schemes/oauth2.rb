# File: lib/adk/auth/schemes/oauth2.rb
# frozen_string_literal: true

require 'oauth2'
require 'securerandom'
require 'digest'
require 'base64'

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

        # @return [Boolean] Whether to use PKCE
        attr_reader :use_pkce
        
        # Initialize a new OAuth2 scheme
        # @param authorization_url [String] The URL for the authorization endpoint
        # @param token_url [String] The URL for the token endpoint
        # @param scopes [Array<String>, String, nil] The requested scopes
        # @param use_pkce [Boolean] Whether to use PKCE
        # @param additional_params [Hash, nil] Additional parameters for authorization requests
        def initialize(authorization_url:, token_url:, scopes: nil, use_pkce: true, additional_params: nil)
          @authorization_url = authorization_url
          @token_url = token_url
          @scopes = parse_scopes(scopes)
          @use_pkce = use_pkce
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
        # @return [Hash] The authorization URI and any additional parameters (like PKCE code verifier)
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
          
          # Generate state for CSRF protection if not provided
          state ||= SecureRandom.hex(16)
          
          # Build the authorization URL with parameters
          params = {
            'client_id' => client_id,
            'response_type' => 'code',
            'redirect_uri' => redirect_uri,
            'state' => state
          }
          
          # Add scopes if present
          params['scope'] = @scopes.join(' ') if @scopes && !@scopes.empty?
          
          # Add PKCE if enabled
          pkce_params = {}
          if @use_pkce
            code_verifier = SecureRandom.alphanumeric(64)
            code_challenge = generate_code_challenge(code_verifier)
            
            params['code_challenge'] = code_challenge
            params['code_challenge_method'] = 'S256'
            
            pkce_params[:code_verifier] = code_verifier
          end
          
          # Add any additional parameters
          params.merge!(@additional_params) if @additional_params
          
          # Remove nil values
          params.compact!
          
          # Build the query string
          require 'uri'
          query = URI.encode_www_form(params)
          
          # Join with the authorization URL
          uri = if @authorization_url.include?('?')
                  "#{@authorization_url}&#{query}"
                else
                  "#{@authorization_url}?#{query}"
                end
          
          {
            uri: uri,
            state: state,
            pkce: pkce_params
          }
        end
        
        # Exchanges an authorization code for tokens
        # @param config [ADK::Auth::Config] The authentication configuration
        # @param credential [ADK::Auth::Credential] The credential with client information
        # @return [ADK::Auth::ExchangedCredential] The exchanged credential with tokens
        # @raise [ADK::Auth::TokenExchangeError] If token exchange fails
        def exchange_token(config, credential)
          unless config.response_uri
            raise ADK::Auth::TokenExchangeError, 'Response URI is required for token exchange'
          end
          
          # Extract the code from the response URI
          uri = URI.parse(config.response_uri)
          params = CGI.parse(uri.query || '')
          code = params['code']&.first
          
          unless code
            raise ADK::Auth::TokenExchangeError, 'Authorization code not found in response URI'
          end
          
          # Verify the state parameter to prevent CSRF attacks
          if config.state && params['state']&.first != config.state
            raise ADK::Auth::TokenExchangeError, 'State parameter mismatch'
          end
          
          begin
            # Create an OAuth2 client
            oauth_client = create_oauth_client(credential)
            
            # Exchange the code for tokens
            auth_params = {
              redirect_uri: config.redirect_uri,
              code: code
            }
            
            # Add PKCE code_verifier if available
            if config.pkce && config.pkce[:code_verifier]
              auth_params[:code_verifier] = config.pkce[:code_verifier]
            end
            
            token = oauth_client.auth_code.get_token(code, auth_params)
            
            # Create an exchanged credential from the token response
            ADK::Auth::ExchangedCredential.new(
              auth_type: :oauth2,
              access_token: token.token,
              refresh_token: token.refresh_token,
              token_type: token.params['token_type'],
              expires_at: token.expires_at ? Time.at(token.expires_at) : nil,
              expires_in: token.expires_in,
              scope: token.params['scope']
            )
          rescue ::OAuth2::Error => e
            raise ADK::Auth::TokenExchangeError, "OAuth2 token exchange failed: #{e.message}"
          rescue StandardError => e
            raise ADK::Auth::TokenExchangeError, "Token exchange failed: #{e.message}"
          end
        end
        
        # Refreshes an access token using a refresh token
        # @param exchanged_credential [ADK::Auth::ExchangedCredential] The credential with the refresh token
        # @param credential [ADK::Auth::Credential] The original credential with client information
        # @return [ADK::Auth::ExchangedCredential] The refreshed credential
        # @raise [ADK::Auth::TokenRefreshError] If token refresh fails
        def refresh_token(exchanged_credential, credential)
          refresh_token = exchanged_credential.refresh_token
          
          unless refresh_token && !refresh_token.empty?
            raise ADK::Auth::TokenRefreshError, 'Refresh token is missing from credential'
          end
          
          begin
            # Create an OAuth2 client
            oauth_client = create_oauth_client(credential)
            
            # Create a token object with the refresh token
            token = ::OAuth2::AccessToken.from_hash(oauth_client, {
              refresh_token: refresh_token,
              expires_at: exchanged_credential.expires_at&.to_i
            })
            
            # Refresh the token
            refreshed_token = token.refresh!
            
            # Create a new exchanged credential with the refreshed token
            ADK::Auth::ExchangedCredential.new(
              auth_type: :oauth2,
              access_token: refreshed_token.token,
              refresh_token: refreshed_token.refresh_token || refresh_token,
              token_type: refreshed_token.params['token_type'],
              expires_at: refreshed_token.expires_at ? Time.at(refreshed_token.expires_at) : nil,
              expires_in: refreshed_token.expires_in,
              scope: refreshed_token.params['scope']
            )
          rescue ::OAuth2::Error => e
            raise ADK::Auth::TokenRefreshError, "OAuth2 token refresh failed: #{e.message}"
          rescue StandardError => e
            raise ADK::Auth::TokenRefreshError, "Token refresh failed: #{e.message}"
          end
        end
        
        # Exchange client credentials for an access token (client credentials flow)
        # @param credential [ADK::Auth::Credential] The credential with client information
        # @return [ADK::Auth::ExchangedCredential] The exchanged credential with tokens
        # @raise [ADK::Auth::TokenExchangeError] If token exchange fails
        def client_credentials_token(credential)
          begin
            # Create an OAuth2 client
            oauth_client = create_oauth_client(credential)
            
            # Request a token using the client credentials flow
            auth_params = {}
            auth_params[:scope] = @scopes.join(' ') if @scopes && !@scopes.empty?
            
            token = oauth_client.client_credentials.get_token(auth_params)
            
            # Create an exchanged credential from the token response
            ADK::Auth::ExchangedCredential.new(
              auth_type: :oauth2,
              access_token: token.token,
              token_type: token.params['token_type'],
              expires_at: token.expires_at ? Time.at(token.expires_at) : nil,
              expires_in: token.expires_in,
              scope: token.params['scope']
            )
          rescue ::OAuth2::Error => e
            raise ADK::Auth::TokenExchangeError, "OAuth2 client credentials exchange failed: #{e.message}"
          rescue StandardError => e
            raise ADK::Auth::TokenExchangeError, "Client credentials exchange failed: #{e.message}"
          end
        end
        
        # Password flow for getting an access token (resource owner password credentials flow)
        # @param credential [ADK::Auth::Credential] The credential with client information
        # @param username [String] The resource owner's username
        # @param password [String] The resource owner's password
        # @return [ADK::Auth::ExchangedCredential] The exchanged credential with tokens
        # @raise [ADK::Auth::TokenExchangeError] If token exchange fails
        def password_token(credential, username, password)
          begin
            # Create an OAuth2 client
            oauth_client = create_oauth_client(credential)
            
            # Request a token using the password flow
            auth_params = {}
            auth_params[:scope] = @scopes.join(' ') if @scopes && !@scopes.empty?
            
            token = oauth_client.password.get_token(username, password, auth_params)
            
            # Create an exchanged credential from the token response
            ADK::Auth::ExchangedCredential.new(
              auth_type: :oauth2,
              access_token: token.token,
              refresh_token: token.refresh_token,
              token_type: token.params['token_type'],
              expires_at: token.expires_at ? Time.at(token.expires_at) : nil,
              expires_in: token.expires_in,
              scope: token.params['scope']
            )
          rescue ::OAuth2::Error => e
            raise ADK::Auth::TokenExchangeError, "OAuth2 password flow failed: #{e.message}"
          rescue StandardError => e
            raise ADK::Auth::TokenExchangeError, "Password flow failed: #{e.message}"
          end
        end
        
        # Convert to a hash
        # @return [Hash] A hash representation of the scheme
        def to_h
          super.merge(
            authorization_url: @authorization_url,
            token_url: @token_url,
            scopes: @scopes,
            use_pkce: @use_pkce,
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
        
        # Generate a code challenge for PKCE
        # @param code_verifier [String] The code verifier
        # @return [String] The code challenge
        def generate_code_challenge(code_verifier)
          # SHA256 hash of the code verifier
          digest = Digest::SHA256.digest(code_verifier)
          # URL-safe base64 encoding without padding
          Base64.urlsafe_encode64(digest, padding: false)
        end
        
        # Create an OAuth2 client
        # @param credential [ADK::Auth::Credential] The credential with client information
        # @return [::OAuth2::Client] The OAuth2 client
        def create_oauth_client(credential)
          client_id = credential[:client_id, resolve_env: true]
          client_secret = credential[:client_secret, resolve_env: true]
          
          unless client_id && !client_id.empty?
            raise ADK::Auth::CredentialError, 'Client ID is missing from credential'
          end
          
          # Note: client_secret can be nil for public clients
          
          # Create the client
          site_uri = URI.parse(@token_url)
          site = "#{site_uri.scheme}://#{site_uri.host}"
          
          ::OAuth2::Client.new(
            client_id,
            client_secret,
            site: site,
            token_url: @token_url,
            authorize_url: @authorization_url
          )
        end
      end
    end
  end
end 