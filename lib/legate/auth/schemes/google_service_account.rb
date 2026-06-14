# frozen_string_literal: true

require 'jwt'
require 'json'
require 'net/http'
require 'base64'
require 'time'
require_relative 'service_account'

module Legate
  module Auth
    module Schemes
      # GoogleServiceAccount implements authentication for Google service accounts
      # using JWT assertions for OAuth 2.0 token exchange
      class GoogleServiceAccount < ServiceAccount
        # Default token URL for Google service accounts
        GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token'

        # Initialize a new GoogleServiceAccount scheme
        # @param audience [String, nil] The audience for the JWT (defaults to token URL)
        # @param scopes [Array<String>, String, nil] The requested scopes
        # @param token_url [String] The URL for token exchange
        # @param token_lifetime [Integer] The token lifetime in seconds
        def initialize(audience: nil, scopes: nil, token_url: GOOGLE_TOKEN_URL, token_lifetime: 3600)
          super(
            token_url: token_url,
            audience: audience || token_url,
            scopes: scopes,
            token_lifetime: token_lifetime
          )
        end

        # @return [Symbol] The scheme type
        def scheme_type
          :google_service_account
        end

        # Fetch a new token using the Google service account
        # @param credential [Legate::Auth::Credential] The credential with service account info
        # @return [Legate::Auth::ExchangedCredential] The exchanged credential with the token
        # @raise [Legate::Auth::TokenExchangeError] If token exchange fails
        def fetch_token(credential)
          # Verify credential type
          raise Legate::Auth::CredentialError, 'Invalid credential type for service account' unless credential.is_a?(Legate::Auth::Credential)

          # Extract service account key from credential
          service_account_key = get_service_account_key(credential)

          # Create and sign the JWT
          jwt = create_signed_jwt(service_account_key)

          # Exchange the JWT for an access token
          token_response = exchange_jwt_for_token(jwt)

          # Create an exchanged credential with the token information
          Legate::Auth::ExchangedCredential.new(
            auth_type: :google_service_account,
            access_token: token_response[:access_token],
            expires_in: token_response[:expires_in],
            token_type: token_response[:token_type],
            scope: token_response[:scope]
          )
        end

        private

        # Create and sign a JWT token for Google service account authentication
        # @param service_account_key [Hash] The service account key data
        # @return [String] The signed JWT
        # @raise [Legate::Auth::TokenExchangeError] If JWT creation fails
        def create_signed_jwt(service_account_key)
          # Verify essential fields in the service account key
          required_fields = %i[client_email private_key type]
          missing_fields = required_fields.reject { |field| service_account_key.key?(field) }

          raise Legate::Auth::CredentialError, "Service account key missing required fields: #{missing_fields.join(', ')}" unless missing_fields.empty?

          # Verify this is a service account key
          raise Legate::Auth::CredentialError, "Invalid key type: #{service_account_key[:type]}, expected 'service_account'" unless service_account_key[:type] == 'service_account'

          # Create the JWT claim set
          now = Time.now.to_i
          claim_set = {
            iss: service_account_key[:client_email],
            aud: @audience,
            exp: now + @token_lifetime,
            iat: now
          }

          # Add scopes if present
          claim_set[:scope] = @scopes.join(' ') if @scopes && !@scopes.empty?

          # Add subject (sub) if present in credential
          claim_set[:sub] = service_account_key[:sub] if service_account_key[:sub]

          begin
            # Create the JWT
            private_key = OpenSSL::PKey::RSA.new(service_account_key[:private_key])

            JWT.encode(claim_set, private_key, 'RS256', { typ: 'JWT' })
          rescue StandardError => e
            raise Legate::Auth::TokenExchangeError, "Failed to create JWT: #{e.message}"
          end
        end
      end
    end
  end
end
