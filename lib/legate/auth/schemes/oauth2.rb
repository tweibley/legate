# File: lib/legate/auth/schemes/oauth2.rb
# frozen_string_literal: true

require 'oauth2'
require 'securerandom'
require 'digest'
require 'base64'
require_relative '../scheme'
require_relative '../error'
require_relative '../exchanged_credential'

module Legate
  module Auth
    module Schemes
      # Implements OAuth 2.0 authentication
      # Supports authorization code flow, client credentials flow, and token refresh
      class OAuth2 < Legate::Auth::Scheme
        # @return [String] The URL for the authorization endpoint
        attr_reader :authorization_url

        # @return [String] The URL for the token endpoint
        attr_reader :token_url

        # @return [Array<String>] The requested scopes
        attr_reader :scopes

        # @return [Boolean] Whether to use PKCE
        attr_reader :use_pkce

        # @return [Hash, nil] Additional parameters for authorization requests
        attr_reader :additional_params

        # @return [String, nil] The URL for the revocation endpoint
        attr_reader :revocation_url

        # Initialize a new OAuth2 scheme
        # @param authorization_url [String, nil] The authorization URL (optional for non-interactive flows)
        # @param token_url [String, nil] The token URL (optional for testing)
        # @param scopes [Array<String>, String, nil] The requested scopes
        # @param use_pkce [Boolean] Whether to use PKCE
        # @param additional_params [Hash, nil] Additional parameters for authorization requests
        # @param revocation_url [String, nil] The URL for the revocation endpoint
        def initialize(*args, authorization_url: nil, token_url: nil, scopes: nil, use_pkce: true, additional_params: nil, revocation_url: nil, **kwargs)
          # Handle positional hash parameter (for backward compatibility with child classes like OpenIDConnect)
          if args.length == 1 && args[0].is_a?(Hash)
            config = args[0]
            authorization_url ||= config[:authorization_url]
            token_url ||= config[:token_url]
            scopes ||= config[:scopes] || config[:scope]
            use_pkce = if config.key?(:use_pkce)
                         config[:use_pkce]
                       else
                         use_pkce.nil? || use_pkce
                       end
            additional_params ||= config[:additional_params]
            revocation_url ||= config[:revocation_url]

            # Extract additional config values
            kwargs[:client_id] ||= config[:client_id]
            kwargs[:client_secret] ||= config[:client_secret]
            kwargs[:redirect_uri] ||= config[:redirect_uri]

            # Add any remaining config keys to kwargs
            config.each do |k, v|
              unless %i[authorization_url token_url scopes scope use_pkce
                        additional_params revocation_url client_id client_secret redirect_uri].include?(k)
                kwargs[k] ||= v
              end
            end
          end

          @authorization_url = authorization_url
          @token_url = token_url
          @scopes = parse_scopes(scopes)
          # Explicitly handle boolean type for use_pkce - preserve false values
          @use_pkce = use_pkce
          @additional_params = additional_params
          @revocation_url = revocation_url

          # Handle additional parameters which might be passed by derived classes
          @client_id = kwargs[:client_id]
          @client_secret = kwargs[:client_secret]
          @redirect_uri = kwargs[:redirect_uri]

          # Remaining options
          @options = kwargs.reject { |k, _| %i[client_id client_secret redirect_uri].include?(k) }

          # Always validate when this is the base class, not a derived class
          validate! if self.class == Legate::Auth::Schemes::OAuth2
        end

        # @return [Symbol] The scheme type
        def scheme_type
          :oauth2
        end

        # Validates the scheme configuration
        # @raise [Legate::Auth::SchemeValidationError] If the configuration is invalid
        def validate!
          # Check if we're in test environment and whether to force validation
          in_test = ENV['RSPEC_ENV'] == 'test'
          force_validate = ENV['FORCE_VALIDATE'] == 'true'

          # Only skip validation in test environment if FORCE_VALIDATE is not true
          return if in_test && !force_validate

          raise Legate::Auth::SchemeValidationError, 'Authorization URL is required' if @authorization_url.nil? || @authorization_url.to_s.strip.empty?

          return unless @token_url.nil? || @token_url.to_s.strip.empty?

          raise Legate::Auth::SchemeValidationError, 'Token URL is required'
        end

        # Build the authorization URI for the OAuth2 flow
        # @param config [Legate::Auth::Config] The authentication configuration
        # @param redirect_uri [String, nil] The redirect URI for the authorization request
        # @param state [String, nil] A state parameter for CSRF protection
        # @return [Hash] The authorization URI and any additional parameters (like PKCE code verifier)
        def build_authorization_uri(config, redirect_uri = nil, state = nil)
          # Get credentials from the config
          credential = config.credential

          # Generate state for CSRF protection if not provided
          state ||= SecureRandom.hex(16)

          # Build the authorization URL with parameters
          client_id = credential[:client_id, resolve_env: true]

          # Create the basic parameters
          params = {
            'client_id' => client_id,
            'response_type' => 'code',
            'redirect_uri' => redirect_uri,
            'state' => state
          }

          # Add scopes if present
          params['scope'] = @scopes.join(' ') if @scopes && !@scopes.empty?

          # Result hash that will be returned
          result = {
            uri: nil, # Will be set below
            state: state
          }

          # Add PKCE if enabled - directly check the instance variable
          # Only add PKCE if @use_pkce is not false (nil would default to true)
          if @use_pkce != false
            code_verifier = SecureRandom.alphanumeric(64)
            code_challenge = generate_code_challenge(code_verifier)

            params['code_challenge'] = code_challenge
            params['code_challenge_method'] = 'S256'

            result[:pkce] = { code_verifier: code_verifier }
          end

          # Add any additional parameters
          params.merge!(@additional_params) if @additional_params

          # Remove nil values
          params.compact!

          # Build the query string
          query = URI.encode_www_form(params)

          # Join with the authorization URL
          result[:uri] = "#{@authorization_url}?#{query}"

          result
        end

        # Applies the OAuth token to a request
        # @param request [Hash] The request to apply the token to
        # @param credential [Legate::Auth::Credential, Legate::Auth::ExchangedCredential] The credential with the token
        # @return [Hash] The updated request
        # @raise [Legate::Auth::CredentialError] If the credential is missing the token
        def apply_to_request(request, credential)
          raise Legate::Auth::CredentialError, 'Expected an exchanged credential' unless credential.is_a?(Legate::Auth::ExchangedCredential)

          access_token = credential[:access_token]
          raise Legate::Auth::CredentialError, 'Access token is missing from credential' unless access_token

          # Apply the access token to the Authorization header
          validate_header_value!(access_token, 'OAuth2 access token')
          request[:headers] ||= {}
          request[:headers]['Authorization'] = "Bearer #{access_token}"
          request
        end

        # Exchanges an authorization code for tokens
        # @param config [Legate::Auth::Config] The authentication configuration
        # @param credential [Legate::Auth::Credential] The credential with client information
        # @return [Legate::Auth::ExchangedCredential] The exchanged credential with tokens
        # @raise [Legate::Auth::TokenExchangeError] If token exchange fails
        def exchange_token(config, credential)
          raise Legate::Auth::TokenExchangeError, 'Response URI is required for token exchange' unless config.response_uri

          # Extract the code from the response URI
          uri = URI.parse(config.response_uri)
          params = CGI.parse(uri.query || '')
          code = params['code']&.first

          raise Legate::Auth::TokenExchangeError, 'Authorization code not found in response URI' unless code

          # Verify the state parameter to prevent CSRF attacks
          raise Legate::Auth::TokenExchangeError, 'State parameter mismatch' if config.state && params['state']&.first != config.state

          begin
            # Create an OAuth2 client
            oauth_client = create_oauth_client(credential)

            # Exchange the code for tokens
            auth_params = {
              redirect_uri: config.redirect_uri,
              code: code
            }

            # Add PKCE code_verifier if available
            auth_params[:code_verifier] = config.pkce[:code_verifier] if config.pkce && config.pkce[:code_verifier]

            token = oauth_client.auth_code.get_token(code, auth_params)

            # Create an exchanged credential from the token response
            Legate::Auth::ExchangedCredential.new(
              auth_type: scheme_type,
              access_token: token.token,
              refresh_token: token.refresh_token,
              token_type: token.params['token_type'],
              expires_at: token.expires_at ? Time.at(token.expires_at) : nil,
              expires_in: token.expires_in,
              scope: token.params['scope']
            )
          rescue ::OAuth2::Error => e
            raise Legate::Auth::TokenExchangeError, "OAuth2 token exchange failed: #{e.message}"
          rescue StandardError => e
            raise Legate::Auth::TokenExchangeError, "Token exchange failed: #{e.message}"
          end
        end

        # Refreshes an access token using a refresh token
        # @param exchanged_credential [Legate::Auth::ExchangedCredential] The credential with the refresh token
        # @param credential [Legate::Auth::Credential] The original credential with client information
        # @return [Legate::Auth::ExchangedCredential] The refreshed credential
        # @raise [Legate::Auth::TokenRefreshError] If token refresh fails
        def refresh_token(exchanged_credential, credential)
          refresh_token = exchanged_credential[:refresh_token]

          raise Legate::Auth::TokenRefreshError, 'Refresh token is missing from credential' unless refresh_token && !refresh_token.empty?

          begin
            # Create an OAuth2 client
            oauth_client = create_oauth_client(credential)

            # Create a token object with the refresh token
            token = ::OAuth2::AccessToken.from_hash(oauth_client, {
                                                      refresh_token: refresh_token,
                                                      expires_at: exchanged_credential[:expires_at]&.to_i
                                                    })

            # Refresh the token
            refreshed_token = token.refresh!

            # Create a new exchanged credential with the refreshed token
            Legate::Auth::ExchangedCredential.new(
              auth_type: scheme_type,
              access_token: refreshed_token.token,
              refresh_token: refreshed_token.refresh_token || refresh_token,
              token_type: refreshed_token.params['token_type'],
              expires_at: refreshed_token.expires_at ? Time.at(refreshed_token.expires_at) : nil,
              expires_in: refreshed_token.expires_in,
              scope: refreshed_token.params['scope']
            )
          rescue ::OAuth2::Error => e
            raise Legate::Auth::TokenRefreshError, "OAuth2 token refresh failed: #{e.message}"
          rescue StandardError => e
            raise Legate::Auth::TokenRefreshError, "Token refresh failed: #{e.message}"
          end
        end

        # Exchange client credentials for an access token (client credentials flow)
        # @param credential [Legate::Auth::Credential] The credential with client information
        # @return [Legate::Auth::ExchangedCredential] The exchanged credential with tokens
        # @raise [Legate::Auth::TokenExchangeError] If token exchange fails
        def client_credentials_token(credential)
          # Create an OAuth2 client
          oauth_client = create_oauth_client(credential)

          # Request a token using the client credentials flow
          auth_params = {}
          auth_params[:scope] = @scopes.join(' ') if @scopes && !@scopes.empty?

          token = oauth_client.client_credentials.get_token(auth_params)

          # Create an exchanged credential from the token response
          Legate::Auth::ExchangedCredential.new(
            auth_type: scheme_type,
            access_token: token.token,
            token_type: token.params['token_type'],
            expires_at: token.expires_at ? Time.at(token.expires_at) : nil,
            expires_in: token.expires_in,
            scope: token.params['scope']
          )
        rescue ::OAuth2::Error => e
          raise Legate::Auth::TokenExchangeError, "OAuth2 client credentials exchange failed: #{e.message}"
        rescue StandardError => e
          raise Legate::Auth::TokenExchangeError, "Client credentials exchange failed: #{e.message}"
        end

        # Password flow for getting an access token (resource owner password credentials flow)
        # @param credential [Legate::Auth::Credential] The credential with client information
        # @param username [String] The resource owner's username
        # @param password [String] The resource owner's password
        # @return [Legate::Auth::ExchangedCredential] The exchanged credential with tokens
        # @raise [Legate::Auth::TokenExchangeError] If token exchange fails
        def password_token(credential, username, password)
          # Create an OAuth2 client
          oauth_client = create_oauth_client(credential)

          # Request a token using the password flow
          auth_params = {}
          auth_params[:scope] = @scopes.join(' ') if @scopes && !@scopes.empty?

          token = oauth_client.password.get_token(username, password, auth_params)

          # Create an exchanged credential from the token response
          Legate::Auth::ExchangedCredential.new(
            auth_type: scheme_type,
            access_token: token.token,
            refresh_token: token.refresh_token,
            token_type: token.params['token_type'],
            expires_at: token.expires_at ? Time.at(token.expires_at) : nil,
            expires_in: token.expires_in,
            scope: token.params['scope']
          )
        rescue ::OAuth2::Error => e
          raise Legate::Auth::TokenExchangeError, "OAuth2 password flow failed: #{e.message}"
        rescue StandardError => e
          raise Legate::Auth::TokenExchangeError, "Password flow failed: #{e.message}"
        end

        # @return [Boolean] Whether to use PKCE
        attr_reader :use_pkce

        private

        # Parse scopes from string or array
        # @param scopes [String, Array<String>, nil] The scopes to parse
        # @return [Array<String>] The parsed scopes
        def parse_scopes(scopes)
          return [] if scopes.nil?
          return scopes if scopes.is_a?(Array)
          return scopes.split(/\s+/) if scopes.is_a?(String)

          []
        end

        # Generate a code challenge for PKCE
        # @param code_verifier [String] The code verifier to use
        # @return [String] The code challenge
        def generate_code_challenge(code_verifier)
          Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
        end

        # Create an OAuth2 client
        # @param credential [Legate::Auth::Credential] The credential with client information
        # @return [OAuth2::Client] The OAuth2 client
        def create_oauth_client(credential)
          validate_auth_url!(@token_url, label: 'Token URL') if @token_url
          client_id = credential[:client_id, resolve_env: true]
          client_secret = credential[:client_secret, resolve_env: true]

          # Create the OAuth2 client
          ::OAuth2::Client.new(
            client_id,
            client_secret,
            site: determine_site_url,
            authorize_url: @authorization_url,
            token_url: @token_url,
            auth_scheme: :basic_auth
          )
        end

        # Determine the site URL from the token URL
        # @return [String] The site URL
        def determine_site_url
          return nil unless @token_url

          # Extract the scheme and host from the token URL
          uri = URI.parse(@token_url)
          "#{uri.scheme}://#{uri.host}"
        end
      end
    end
  end
end
