# frozen_string_literal: true

require 'webmock/rspec'
require 'json'
require 'base64'
require 'openssl'

module Legate
  module Test
    module Support
      # MockAuthProviders contains classes for mocking various authentication providers
      # such as OAuth2, OpenID Connect, and service accounts for testing purposes
      module MockAuthProviders
        # Configuration for mock providers
        class Config
          attr_accessor :token_expiry_seconds, :use_custom_claims, :custom_claims, :jwks_uri, :authorization_endpoint, :token_endpoint, :userinfo_endpoint, :issuer, :client_id, :client_secret, :redirect_uri

          def initialize
            @token_expiry_seconds = 3600
            @use_custom_claims = false
            @custom_claims = {}

            # Default endpoints
            @issuer = 'https://mock-auth.example.com'
            @authorization_endpoint = "#{@issuer}/oauth/authorize"
            @token_endpoint = "#{@issuer}/oauth/token"
            @jwks_uri = "#{@issuer}/.well-known/jwks.json"
            @userinfo_endpoint = "#{@issuer}/userinfo"

            # Default test client credentials
            @client_id = 'test-client-id'
            @client_secret = 'test-client-secret'
            @redirect_uri = 'http://localhost:8000/callback'
          end
        end

        # Base class for mock auth providers
        class MockProvider
          attr_reader :config, :key_pair, :jwk

          def initialize(config = nil)
            @config = config || Config.new

            # Generate RSA key pair for token signing
            @key_pair = OpenSSL::PKey::RSA.new(2048)

            # Create JWK representation
            @jwk = {
              kty: 'RSA',
              alg: 'RS256',
              use: 'sig',
              kid: SecureRandom.uuid,
              n: Base64.urlsafe_encode64(@key_pair.n.to_s(2)).gsub(/=+$/, ''),
              e: Base64.urlsafe_encode64(@key_pair.e.to_s(2)).gsub(/=+$/, '')
            }
          end

          # Mock JWT token creation
          def create_jwt(sub, aud = nil, additional_claims = {})
            now = Time.now.to_i

            claims = {
              iss: config.issuer,
              sub: sub,
              aud: aud || config.client_id,
              iat: now,
              exp: now + config.token_expiry_seconds,
              jti: SecureRandom.uuid
            }

            claims.merge!(additional_claims)
            claims.merge!(config.custom_claims) if config.use_custom_claims

            # In a real implementation we would use JWT gem to create and sign the token
            # For now, we'll return a mock token
            header = Base64.urlsafe_encode64({ alg: 'RS256', typ: 'JWT', kid: jwk[:kid] }.to_json)
            payload = Base64.urlsafe_encode64(claims.to_json)
            signature = 'mock_signature' # In real code this would be signed

            "#{header}.#{payload}.#{signature}"
          end

          # Setup stubs for common endpoints
          def setup_stubs
            # To be implemented by subclasses
          end
        end

        # OAuth2 mock provider
        class MockOAuth2Provider < MockProvider
          def setup_stubs
            # Mock discovery document
            WebMock.stub_request(:get, "#{config.issuer}/.well-known/oauth-authorization-server")
                   .to_return(
                     status: 200,
                     headers: { 'Content-Type' => 'application/json' },
                     body: {
                       issuer: config.issuer,
                       authorization_endpoint: config.authorization_endpoint,
                       token_endpoint: config.token_endpoint,
                       jwks_uri: config.jwks_uri,
                       response_types_supported: %w[code token],
                       grant_types_supported: %w[authorization_code refresh_token client_credentials],
                       token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post]
                     }.to_json
                   )

            # Mock JWKS endpoint for token verification
            WebMock.stub_request(:get, config.jwks_uri)
                   .to_return(
                     status: 200,
                     headers: { 'Content-Type' => 'application/json' },
                     body: {
                       keys: [jwk]
                     }.to_json
                   )

            # Mock token endpoint
            WebMock.stub_request(:post, config.token_endpoint)
                   .to_return do |request|
                     body = URI.decode_www_form(request.body).to_h
                     grant_type = body['grant_type']

                     case grant_type
                     when 'authorization_code'
                       handle_authorization_code_grant(body)
                     when 'refresh_token'
                       handle_refresh_token_grant(body)
                     when 'client_credentials'
                       handle_client_credentials_grant(body)
                     else
                       {
                         status: 400,
                         headers: { 'Content-Type' => 'application/json' },
                         body: { error: 'unsupported_grant_type' }.to_json
                       }
                     end
                   end
          end

          private

          def handle_authorization_code_grant(params)
            code = params['code']

            # In a real implementation we would validate the code
            # For testing, we'll accept any code

            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                access_token: create_jwt('user_123'),
                token_type: 'Bearer',
                expires_in: config.token_expiry_seconds,
                refresh_token: "refresh_#{SecureRandom.hex(16)}"
              }.to_json
            }
          end

          def handle_refresh_token_grant(params)
            refresh_token = params['refresh_token']

            # In a real implementation we would validate the refresh token
            # For testing, we'll accept any refresh token that starts with "refresh_"

            if refresh_token.start_with?('refresh_')
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  access_token: create_jwt('user_123'),
                  token_type: 'Bearer',
                  expires_in: config.token_expiry_seconds,
                  refresh_token: "refresh_#{SecureRandom.hex(16)}"
                }.to_json
              }
            else
              {
                status: 400,
                headers: { 'Content-Type' => 'application/json' },
                body: { error: 'invalid_grant' }.to_json
              }
            end
          end

          def handle_client_credentials_grant(_params)
            # In a real implementation we would validate client credentials

            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                access_token: create_jwt("client_#{config.client_id}"),
                token_type: 'Bearer',
                expires_in: config.token_expiry_seconds
              }.to_json
            }
          end
        end

        # OpenID Connect mock provider
        class MockOpenIDConnectProvider < MockOAuth2Provider
          def setup_stubs
            # Call parent to set up basic OAuth2 endpoints
            super

            # Add OIDC-specific endpoints

            # Mock OIDC discovery document
            WebMock.stub_request(:get, "#{config.issuer}/.well-known/openid-configuration")
                   .to_return(
                     status: 200,
                     headers: { 'Content-Type' => 'application/json' },
                     body: {
                       issuer: config.issuer,
                       authorization_endpoint: config.authorization_endpoint,
                       token_endpoint: config.token_endpoint,
                       userinfo_endpoint: config.userinfo_endpoint,
                       jwks_uri: config.jwks_uri,
                       response_types_supported: ['code', 'token', 'id_token', 'code id_token', 'code token', 'id_token token', 'code id_token token'],
                       subject_types_supported: %w[public pairwise],
                       id_token_signing_alg_values_supported: ['RS256'],
                       scopes_supported: %w[openid email profile address phone],
                       token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post],
                       claims_supported: %w[sub iss auth_time name given_name family_name email email_verified]
                     }.to_json
                   )

            # Mock userinfo endpoint
            WebMock.stub_request(:get, config.userinfo_endpoint)
                   .with(headers: { 'Authorization' => /Bearer .+/ })
                   .to_return do |request|
                     auth_header = request.headers['Authorization']
                     token = auth_header&.split(' ')&.last

                     if token && token.include?('.') # Simple check if it looks like a JWT
                       {
                         status: 200,
                         headers: { 'Content-Type' => 'application/json' },
                         body: {
                           sub: 'user_123',
                           name: 'Test User',
                           given_name: 'Test',
                           family_name: 'User',
                           email: 'test@example.com',
                           email_verified: true
                         }.to_json
                       }
                     else
                       {
                         status: 401,
                         headers: { 'Content-Type' => 'application/json' },
                         body: { error: 'invalid_token' }.to_json
                       }
                     end
                   end
          end

          # Override to add id_token to authorization code response
          def handle_authorization_code_grant(params)
            response = super

            # Parse the response body
            body = JSON.parse(response[:body])

            # Add id_token if response was successful
            if response[:status] == 200
              body['id_token'] = create_id_token('user_123')
              response[:body] = body.to_json
            end

            response
          end

          private

          def create_id_token(sub, nonce = nil)
            additional_claims = {
              auth_time: Time.now.to_i,
              name: 'Test User',
              email: 'test@example.com'
            }

            additional_claims[:nonce] = nonce if nonce

            create_jwt(sub, config.client_id, additional_claims)
          end
        end

        # Service Account mock provider
        class MockServiceAccountProvider < MockProvider
          def setup_stubs
            # Mock token endpoint for service account JWT assertion
            WebMock.stub_request(:post, "#{config.issuer}/token")
                   .with(body: WebMock.hash_including('grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer'))
                   .to_return do |request|
                     body = URI.decode_www_form(request.body).to_h
                     jwt_assertion = body['assertion']

                     # In a real implementation, we would validate the JWT
                     # For testing, we'll accept any JWT

                     {
                       status: 200,
                       headers: { 'Content-Type' => 'application/json' },
                       body: {
                         access_token: create_jwt('service_account_123'),
                         token_type: 'Bearer',
                         expires_in: config.token_expiry_seconds
                       }.to_json
                     }
                   end

            # Mock JWKS endpoint
            WebMock.stub_request(:get, config.jwks_uri)
                   .to_return(
                     status: 200,
                     headers: { 'Content-Type' => 'application/json' },
                     body: {
                       keys: [jwk]
                     }.to_json
                   )
          end
        end

        # Google Service Account mock provider
        class MockGoogleServiceAccountProvider < MockServiceAccountProvider
          def initialize(config = nil)
            super(config)
            @config.issuer = 'https://oauth2.googleapis.com'
          end

          def setup_stubs
            super

            # Mock token endpoint specific to Google
            WebMock.stub_request(:post, 'https://oauth2.googleapis.com/token')
                   .with(body: WebMock.hash_including('grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer'))
                   .to_return do |request|
                     body = URI.decode_www_form(request.body).to_h
                     jwt_assertion = body['assertion']

                     {
                       status: 200,
                       headers: { 'Content-Type' => 'application/json' },
                       body: {
                         access_token: "ya29.mock_google_token_#{SecureRandom.hex(16)}",
                         expires_in: config.token_expiry_seconds,
                         token_type: 'Bearer'
                       }.to_json
                     }
                   end
          end
        end
      end
    end
  end
end
