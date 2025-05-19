# frozen_string_literal: true

require 'jwt'
require 'json'
require 'net/http'
require 'base64'
require 'uri'
require 'openssl'
require 'time'
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
        
        # Default token lifetime in seconds
        DEFAULT_TOKEN_LIFETIME = 3600
        
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
            auth_type: scheme_type,
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
        
        # Check if this scheme supports token refresh
        # @return [Boolean] True if this scheme supports token refresh
        def supports_refresh?
          true
        end
        
        # Refresh an authentication token
        # @param token [ADK::Auth::ExchangedCredential] The token to refresh
        # @param credential [ADK::Auth::Credential] The credential containing refresh parameters
        # @return [ADK::Auth::ExchangedCredential] The refreshed token
        # @raise [ADK::Auth::TokenRefreshError] If the token cannot be refreshed
        def refresh_token(token, credential)
          # For service accounts, we just get a new token
          exchange_token(credential)
        end
        
        # Exchange a service account credential for a token
        # @param credential [ADK::Auth::Credential] The credential to exchange
        # @return [ADK::Auth::ExchangedCredential] The exchanged token
        # @raise [ADK::Auth::TokenExchangeError] If the credential cannot be exchanged
        def exchange_token(credential)
          # Get required credential fields
          client_email = credential[:client_email]
          private_key = credential[:private_key]
          token_uri = credential[:token_uri]
          
          # Validate required fields
          unless client_email && private_key && token_uri
            missing = []
            missing << 'client_email' unless client_email
            missing << 'private_key' unless private_key
            missing << 'token_uri' unless token_uri
            
            raise ADK::Auth::TokenExchangeError, "Missing required service account fields: #{missing.join(', ')}"
          end
          
          # Get optional fields
          scope = credential[:scope]
          audience = credential[:audience]
          subject = credential[:subject]
          additional_claims = credential[:additional_claims] || {}
          token_lifetime = credential[:token_lifetime] || DEFAULT_TOKEN_LIFETIME
          
          # At least one of scope or audience must be provided
          unless scope || audience
            raise ADK::Auth::TokenExchangeError, 'Either scope or audience must be provided'
          end
          
          # Create JWT claim set
          now = Time.now.to_i
          claim_set = {
            'iss' => client_email,
            'iat' => now,
            'exp' => now + token_lifetime
          }
          
          # Add scope or audience depending on grant type
          if scope
            claim_set['scope'] = scope
          else
            claim_set['aud'] = audience
          end
          
          # Add subject if provided (for domain-wide delegation)
          claim_set['sub'] = subject if subject
          
          # Add any additional claims
          claim_set.merge!(additional_claims)
          
          # Create JWT header
          header = { 'alg' => 'RS256', 'typ' => 'JWT' }
          
          # Create JWT
          encoded_header = Base64.urlsafe_encode64(JSON.generate(header)).gsub(/=+$/, '')
          encoded_claims = Base64.urlsafe_encode64(JSON.generate(claim_set)).gsub(/=+$/, '')
          signature_base = "#{encoded_header}.#{encoded_claims}"
          
          # Sign the JWT
          begin
            key = OpenSSL::PKey::RSA.new(private_key)
            signature = key.sign(OpenSSL::Digest::SHA256.new, signature_base)
            encoded_signature = Base64.urlsafe_encode64(signature).gsub(/=+$/, '')
            jwt = "#{signature_base}.#{encoded_signature}"
          rescue StandardError => e
            raise ADK::Auth::TokenExchangeError, "Error signing JWT: #{e.message}"
          end
          
          # Exchange JWT for access token
          uri = URI(token_uri)
          request = Net::HTTP::Post.new(uri)
          request['Content-Type'] = 'application/x-www-form-urlencoded'
          
          # Set form parameters based on grant type
          if scope
            # OAuth 2.0 JWT Bearer Grant Type
            request.set_form_data({
              'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
              'assertion' => jwt
            })
          else
            # Self-issued JWT
            return ADK::Auth::ExchangedCredential.new(
              auth_type: :service_account,
              access_token: jwt,
              token_type: 'Bearer',
              expires_at: Time.at(claim_set['exp']),
              raw_data: claim_set
            )
          end
          
          # Send request
          response = nil
          begin
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            http.verify_mode = OpenSSL::SSL::VERIFY_PEER
            response = http.request(request)
          rescue StandardError => e
            raise ADK::Auth::TokenExchangeError, "Error exchanging token: #{e.message}"
          end
          
          # Handle response
          unless response.is_a?(Net::HTTPSuccess)
            raise ADK::Auth::TokenExchangeError, "Token exchange failed: #{response.code} #{response.message}"
          end
          
          # Parse response
          begin
            data = JSON.parse(response.body)
          rescue JSON::ParserError => e
            raise ADK::Auth::TokenExchangeError, "Error parsing token response: #{e.message}"
          end
          
          # Check for error in response
          if data['error']
            raise ADK::Auth::TokenExchangeError, "OAuth2 error: #{data['error']} - #{data['error_description']}"
          end
          
          # Extract token details
          access_token = data['access_token']
          token_type = data['token_type'] || 'Bearer'
          expires_in = data['expires_in'] || token_lifetime
          
          unless access_token
            raise ADK::Auth::TokenExchangeError, 'Access token not found in response'
          end
          
          # Create expiration timestamp
          expires_at = Time.now + expires_in.to_i
          
          # Create the exchanged credential
          ADK::Auth::ExchangedCredential.new(
            auth_type: :service_account,
            access_token: access_token,
            token_type: token_type,
            expires_at: expires_at,
            scope: data['scope'] || scope,
            raw_data: data
          )
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