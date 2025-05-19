# frozen_string_literal: true

require 'jwt'
require 'json'
require 'net/http'
require 'base64'
require 'time'
require_relative 'service_account'

module ADK
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
        
        private
        
        # Create and sign a JWT token for Google service account authentication
        # @param service_account_key [Hash] The service account key data
        # @return [String] The signed JWT
        # @raise [ADK::Auth::TokenExchangeError] If JWT creation fails
        def create_signed_jwt(service_account_key)
          # Verify essential fields in the service account key
          required_fields = [:client_email, :private_key, :type]
          missing_fields = required_fields.reject { |field| service_account_key.key?(field) }
          
          unless missing_fields.empty?
            raise ADK::Auth::CredentialError, "Service account key missing required fields: #{missing_fields.join(', ')}"
          end
          
          # Verify this is a service account key
          unless service_account_key[:type] == 'service_account'
            raise ADK::Auth::CredentialError, "Invalid key type: #{service_account_key[:type]}, expected 'service_account'"
          end
          
          # Create the JWT claim set
          now = Time.now.to_i
          claim_set = {
            iss: service_account_key[:client_email],
            aud: @audience,
            exp: now + @token_lifetime,
            iat: now
          }
          
          # Add scopes if present
          if @scopes && !@scopes.empty?
            claim_set[:scope] = @scopes.join(' ')
          end
          
          # Add subject (sub) if present in credential
          if service_account_key[:sub]
            claim_set[:sub] = service_account_key[:sub]
          end
          
          begin
            # Create the JWT
            private_key = OpenSSL::PKey::RSA.new(service_account_key[:private_key])
            
            JWT.encode(claim_set, private_key, 'RS256', { typ: 'JWT' })
          rescue StandardError => e
            raise ADK::Auth::TokenExchangeError, "Failed to create JWT: #{e.message}"
          end
        end
      end
    end
  end
end 