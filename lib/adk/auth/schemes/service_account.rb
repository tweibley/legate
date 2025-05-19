# frozen_string_literal: true

require 'jwt'
require 'json'
require 'net/http'
require 'base64'
require 'uri'
require_relative '../scheme'
require_relative '../error'
require_relative '../credential'
require_relative '../exchanged_credential'

module ADK
  module Auth
    module Schemes
      # ServiceAccount implements authentication for service account credentials
      # using JWT assertions with various cloud providers
      class ServiceAccount < Scheme
        # @return [String] The token URL for exchanging service account JWTs
        attr_reader :token_url
        
        # @return [String, nil] The audience for the JWT
        attr_reader :audience
        
        # @return [Array<String>] The scopes for the token request
        attr_reader :scopes
        
        # @return [Integer] The JWT token lifetime in seconds (default: 1 hour)
        attr_reader :token_lifetime
        
        # Initialize a new ServiceAccount scheme
        # @param token_url [String] The URL for token exchange
        # @param audience [String, nil] The audience for the JWT
        # @param scopes [Array<String>, String, nil] The requested scopes
        # @param token_lifetime [Integer] The token lifetime in seconds
        def initialize(token_url:, audience: nil, scopes: nil, token_lifetime: 3600)
          @token_url = token_url
          @audience = audience
          @scopes = parse_scopes(scopes)
          @token_lifetime = token_lifetime
          
          validate!
        end
        
        # @return [Symbol] The scheme type
        def scheme_type
          :service_account
        end
        
        # Validates the scheme configuration
        # @raise [ADK::Auth::SchemeValidationError] If the configuration is invalid
        def validate!
          if @token_url.nil? || @token_url.empty?
            raise ADK::Auth::SchemeValidationError, 'Token URL is required for service account authentication'
          end
          
          if @token_lifetime <= 0
            raise ADK::Auth::SchemeValidationError, 'Token lifetime must be positive'
          end
        end
        
        # Apply the authentication to a request
        # @param request [Hash] The request to modify with authentication
        # @param credential [ADK::Auth::ExchangedCredential] The credential with the token
        # @return [Hash] The modified request
        # @raise [ADK::Auth::CredentialError] If the credential is invalid
        def apply_to_request(request, credential)
          unless credential.is_a?(ADK::Auth::ExchangedCredential)
            raise ADK::Auth::CredentialError, 'Expected an exchanged credential'
          end
          
          unless credential.access_token
            raise ADK::Auth::CredentialError, 'Access token is missing from credential'
          end
          
          # Add the Authorization header with the bearer token
          request[:headers] ||= {}
          request[:headers]['Authorization'] = "Bearer #{credential.access_token}"
          
          request
        end
        
        # Fetch a new token using the service account
        # @param credential [ADK::Auth::Credential] The credential with service account info
        # @return [ADK::Auth::ExchangedCredential] The exchanged credential with the token
        # @raise [ADK::Auth::TokenExchangeError] If token exchange fails
        def fetch_token(credential)
          # Verify credential type
          unless credential.is_a?(ADK::Auth::Credential)
            raise ADK::Auth::CredentialError, 'Invalid credential type for service account'
          end
          
          # Extract service account key from credential
          service_account_key = get_service_account_key(credential)
          
          # Create and sign the JWT
          jwt = create_signed_jwt(service_account_key)
          
          # Exchange the JWT for an access token
          token_response = exchange_jwt_for_token(jwt)
          
          # Create an exchanged credential with the token information
          ADK::Auth::ExchangedCredential.new(
            auth_type: :service_account,
            access_token: token_response[:access_token],
            expires_in: token_response[:expires_in],
            token_type: token_response[:token_type],
            scope: token_response[:scope]
          )
        end
        
        # Convert to a hash
        # @return [Hash] A hash representation of the scheme
        def to_h
          {
            type: scheme_type,
            token_url: @token_url,
            audience: @audience,
            scopes: @scopes,
            token_lifetime: @token_lifetime
          }.compact
        end
        
        private
        
        # Parse scopes from a string or array
        # @param scopes [String, Array, nil] The scopes to parse
        # @return [Array<String>] The parsed scopes
        def parse_scopes(scopes)
          return [] unless scopes
          
          if scopes.is_a?(String)
            scopes.split(/\s+/)
          else
            Array(scopes)
          end
        end
        
        # Get the service account key from a credential
        # @param credential [ADK::Auth::Credential] The credential with service account info
        # @return [Hash] The parsed service account key data
        # @raise [ADK::Auth::CredentialError] If the service account key is invalid
        def get_service_account_key(credential)
          # Check for service_account_key in credential
          key_json = credential[:service_account_key, resolve_env: true]
          
          # If not present, check for service_account_key_file
          if key_json.nil? || key_json.empty?
            key_file = credential[:service_account_key_file, resolve_env: true]
            if key_file && !key_file.empty?
              begin
                key_json = File.read(key_file)
              rescue StandardError => e
                raise ADK::Auth::CredentialError, "Failed to read service account key file: #{e.message}"
              end
            end
          end
          
          # Parse the key JSON
          begin
            if key_json && !key_json.empty?
              JSON.parse(key_json, symbolize_names: true)
            else
              raise ADK::Auth::CredentialError, 'No service account key found in credential'
            end
          rescue JSON::ParserError => e
            raise ADK::Auth::CredentialError, "Invalid service account key format: #{e.message}"
          end
        end
        
        # Create and sign a JWT token for service account authentication
        # @param service_account_key [Hash] The service account key data
        # @return [String] The signed JWT
        # @raise [ADK::Auth::TokenExchangeError] If JWT creation fails
        def create_signed_jwt(service_account_key)
          # This is a base implementation - subclasses should override
          # with provider-specific implementations
          raise NotImplementedError, 'Subclasses must implement create_signed_jwt'
        end
        
        # Exchange a JWT for an access token
        # @param jwt [String] The signed JWT to exchange
        # @return [Hash] The token response data
        # @raise [ADK::Auth::TokenExchangeError] If token exchange fails
        def exchange_jwt_for_token(jwt)
          begin
            # Create the HTTP request
            uri = URI.parse(@token_url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            
            # Prepare the request
            request = Net::HTTP::Post.new(uri.request_uri)
            request.content_type = 'application/x-www-form-urlencoded'
            
            # Set the request body
            request.body = URI.encode_www_form({
              grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
              assertion: jwt
            })
            
            # Send the request
            response = http.request(request)
            
            # Handle the response
            if response.is_a?(Net::HTTPSuccess)
              parsed_response = JSON.parse(response.body, symbolize_names: true)
              
              # Convert string keys to symbols if needed
              parsed_response = parsed_response.transform_keys(&:to_sym) if parsed_response.keys.first.is_a?(String)
              
              # Verify required fields
              unless parsed_response[:access_token] && parsed_response[:token_type]
                raise ADK::Auth::TokenExchangeError, 'Token response missing required fields'
              end
              
              parsed_response
            else
              error_body = begin
                JSON.parse(response.body, symbolize_names: true)
              rescue
                { error: 'unknown_error', error_description: response.body }
              end
              
              error_message = error_body[:error_description] || error_body[:error] || "HTTP #{response.code}"
              raise ADK::Auth::TokenExchangeError, "Token exchange failed: #{error_message}"
            end
          rescue StandardError => e
            if e.is_a?(ADK::Auth::TokenExchangeError)
              raise e
            else
              raise ADK::Auth::TokenExchangeError, "Token exchange failed: #{e.message}"
            end
          end
        end
      end
    end
  end
end 