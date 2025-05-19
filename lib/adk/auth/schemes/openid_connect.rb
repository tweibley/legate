# File: lib/adk/auth/schemes/openid_connect.rb
# frozen_string_literal: true

require 'oauth2'
require 'securerandom'
require 'net/http'
require 'json'
require 'jwt'
require_relative 'oauth2'

module ADK
  module Auth
    module Schemes
      # Implements OpenID Connect authentication
      # Extends OAuth2 with OpenID Connect specific features
      class OpenIDConnect < OAuth2
        # @return [String, nil] The URL for the OpenID Connect discovery document
        attr_reader :discovery_url
        
        # @return [String, nil] The URL for the JWK Set
        attr_reader :jwks_url
        
        # @return [String, nil] The userinfo endpoint URL
        attr_reader :userinfo_url
        
        # @return [String, nil] The issuer identifier
        attr_reader :issuer
        
        # Initialize a new OpenID Connect scheme
        # @param authorization_url [String, nil] The URL for the authorization endpoint (optional if discovery_url is provided)
        # @param token_url [String, nil] The URL for the token endpoint (optional if discovery_url is provided)
        # @param discovery_url [String, nil] The URL for the OpenID Connect discovery document
        # @param jwks_url [String, nil] The URL for the JWKS endpoint
        # @param scopes [Array<String>, String, nil] The requested scopes
        # @param use_pkce [Boolean] Whether to use PKCE
        # @param additional_params [Hash, nil] Additional parameters for authorization requests
        def initialize(authorization_url: nil, token_url: nil, discovery_url: nil, jwks_url: nil,
                       scopes: nil, use_pkce: true, additional_params: nil)
          @discovery_url = discovery_url
          @jwks_url = jwks_url
          @userinfo_url = nil
          @issuer = nil
          
          # If discovery URL is provided, attempt to fetch the endpoints
          if @discovery_url && (!authorization_url || !token_url || !@jwks_url)
            begin
              discovery_data = fetch_discovery_document
              authorization_url ||= discovery_data[:authorization_endpoint]
              token_url ||= discovery_data[:token_endpoint]
              @jwks_url ||= discovery_data[:jwks_uri]
              @userinfo_url = discovery_data[:userinfo_endpoint]
              @issuer = discovery_data[:issuer]
            rescue StandardError => e
              # Log the error but don't fail immediately, as endpoints might be provided directly
              warn "Failed to fetch OIDC discovery document: #{e.message}"
            end
          end
          
          # Ensure the openid scope is included
          full_scopes = parse_scopes(scopes)
          full_scopes << 'openid' unless full_scopes.include?('openid')
          
          # Initialize the OAuth2 parent class
          super(
            authorization_url: authorization_url,
            token_url: token_url,
            scopes: full_scopes,
            use_pkce: use_pkce,
            additional_params: additional_params
          )
          
          # Store discovery-specific information
          @jwks_cache = {}
          @jwks_cache_timestamp = nil
        end
        
        # @return [Symbol] The scheme type
        def scheme_type
          :openid_connect
        end
        
        # Validates the scheme configuration
        # @raise [ADK::Auth::SchemeValidationError] If the configuration is invalid
        def validate!
          # If we have a discovery URL, don't need endpoints immediately
          return if @discovery_url && !@discovery_url.empty?
          
          # Otherwise, validate the OAuth2 configuration
          super
        end
        
        # Build the authorization URI for the OpenID Connect flow
        # @param config [ADK::Auth::Config] The authentication configuration
        # @param redirect_uri [String, nil] The redirect URI for the authorization request
        # @param state [String, nil] A state parameter for CSRF protection
        # @return [Hash] The authorization URI and additional parameters
        def build_authorization_uri(config, redirect_uri = nil, state = nil)
          # Make sure we have loaded configuration from discovery if needed
          ensure_endpoints_available
          
          # Generate a nonce for OIDC
          nonce = SecureRandom.hex(16)
          
          # Initialize options hash if not present
          config.options ||= {}
          
          # Store the nonce in the config options
          config.options[:nonce] = nonce
          
          # Add OIDC-specific parameters
          additional_params = (@additional_params || {}).merge({
            'response_type' => 'code',
            'nonce' => nonce
          })
          
          # Create a temporary scheme for URI building
          temp_scheme = OAuth2.new(
            authorization_url: @authorization_url,
            token_url: @token_url,
            scopes: @scopes,
            use_pkce: @use_pkce,
            additional_params: additional_params
          )
          
          # Use the OAuth2 implementation to build the URI
          temp_scheme.build_authorization_uri(config, redirect_uri, state)
        end
        
        # Exchanges an authorization code for tokens
        # @param config [ADK::Auth::Config] The authentication configuration
        # @param credential [ADK::Auth::Credential] The credential with client information
        # @return [ADK::Auth::ExchangedCredential] The exchanged credential with tokens
        # @raise [ADK::Auth::TokenExchangeError] If token exchange fails
        def exchange_token(config, credential)
          # First, get the tokens using OAuth2's implementation
          oauth2_credential = super
          
          # Extract the ID token from the token response 
          # Try different possible locations where the ID token might be stored
          id_token = oauth2_credential.id_token ||
                     oauth2_credential.attributes&.dig(:id_token) ||
                     oauth2_credential.attributes&.dig(:params, 'id_token')
          
          # Initialize user_info as empty hash
          user_info = {}
          
          # Verify the ID token if present
          if id_token
            begin
              # Get client ID for verification
              client_id = credential[:client_id, resolve_env: true]
              
              # Verify the token's signature and claims
              decoded_token = verify_id_token(id_token, config.options[:nonce], client_id)
              
              # Extract user information from the ID token
              user_info = extract_user_info(decoded_token)
            rescue StandardError => e
              raise ADK::Auth::TokenExchangeError, "ID token verification failed: #{e.message}"
            end
          end
          
          # Create an exchanged credential with OIDC specifics
          ADK::Auth::ExchangedCredential.new(
            auth_type: scheme_type,
            access_token: oauth2_credential.access_token,
            refresh_token: oauth2_credential.refresh_token,
            token_type: oauth2_credential.token_type,
            expires_at: oauth2_credential.expires_at,
            expires_in: oauth2_credential.expires_in,
            scope: oauth2_credential[:scope],
            id_token: id_token,
            user_info: user_info
          )
        end
        
        # Fetches user information using the userinfo endpoint
        # @param exchanged_credential [ADK::Auth::ExchangedCredential] The credential with the access token
        # @return [Hash] The user information
        # @raise [ADK::Auth::Error] If the userinfo request fails
        def fetch_userinfo(exchanged_credential)
          unless @userinfo_url
            ensure_endpoints_available
            
            unless @userinfo_url
              raise ADK::Auth::ConfigurationError, 'Userinfo endpoint URL not available'
            end
          end
          
          begin
            # Create a request with the access token
            uri = URI.parse(@userinfo_url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            
            request = Net::HTTP::Get.new(uri.request_uri)
            request['Authorization'] = "Bearer #{exchanged_credential.access_token}"
            
            response = http.request(request)
            
            if response.is_a?(Net::HTTPSuccess)
              JSON.parse(response.body, symbolize_names: true)
            else
              raise ADK::Auth::Error, "Userinfo request failed: #{response.code} #{response.message}"
            end
          rescue StandardError => e
            raise ADK::Auth::Error, "Failed to fetch user information: #{e.message}"
          end
        end
        
        # Convert to a hash
        # @return [Hash] A hash representation of the scheme
        def to_h
          super.merge(
            discovery_url: @discovery_url,
            jwks_url: @jwks_url
          ).compact
        end
        
        private
        
        # Ensure endpoints are available, fetching from discovery if needed
        # @raise [ADK::Auth::ConfigurationError] If endpoints cannot be resolved
        def ensure_endpoints_available
          return if @authorization_url && @token_url
          
          unless @discovery_url
            raise ADK::Auth::ConfigurationError, 'Either endpoints or discovery URL must be provided'
          end
          
          discovery_data = fetch_discovery_document
          @authorization_url ||= discovery_data[:authorization_endpoint]
          @token_url ||= discovery_data[:token_endpoint]
          @jwks_url ||= discovery_data[:jwks_uri]
          @userinfo_url ||= discovery_data[:userinfo_endpoint]
          @issuer ||= discovery_data[:issuer]
          
          unless @authorization_url && @token_url
            raise ADK::Auth::ConfigurationError, 'Could not resolve endpoints from discovery document'
          end
        end
        
        # Fetch and parse the OpenID Connect discovery document
        # @return [Hash] The parsed discovery document
        # @raise [ADK::Auth::ConfigurationError] If the discovery document cannot be fetched or parsed
        def fetch_discovery_document
          begin
            uri = URI.parse(@discovery_url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            
            request = Net::HTTP::Get.new(uri.request_uri)
            response = http.request(request)
            
            if response.is_a?(Net::HTTPSuccess)
              JSON.parse(response.body, symbolize_names: true)
            else
              raise ADK::Auth::ConfigurationError, "Discovery request failed: #{response.code} #{response.message}"
            end
          rescue StandardError => e
            raise ADK::Auth::ConfigurationError, "Failed to fetch discovery document: #{e.message}"
          end
        end
        
        # Verify an ID token's signature and claims
        # @param id_token [String] The ID token to verify
        # @param nonce [String, nil] The nonce to verify against
        # @param client_id [String, nil] The client ID to verify against (defaults to nil)
        # @return [Hash] The decoded token payload
        # @raise [StandardError] If verification fails
        def verify_id_token(id_token, nonce = nil, client_id = nil)
          # Decode the token header to get the key ID and algorithm
          header = JWT.decode(id_token, nil, false)[1]
          kid = header['kid']
          alg = header['alg']
          
          # Fetch the JWK Set if needed
          jwks = fetch_jwks
          
          # Find the JWK with the matching key ID
          jwk = jwks[:keys].find { |key| key[:kid] == kid }
          unless jwk
            raise ADK::Auth::TokenExchangeError, "JWK with key ID #{kid} not found"
          end
          
          # Convert the JWK to a public key
          public_key = jwk_to_key(jwk, alg)
          
          # Prepare verify options
          verify_options = {
            algorithm: alg,
            verify_iat: true,
            verify_iss: true,
            iss: @issuer
          }
          
          # Add audience verification if client_id is provided
          if client_id
            verify_options[:verify_aud] = true
            verify_options[:aud] = client_id
          end
          
          # Add nonce verification if provided
          if nonce
            verify_options[:verify_nonce] = true
            verify_options[:nonce] = nonce
          end
          
          # Verify the token
          decoded_token = JWT.decode(
            id_token,
            public_key,
            true,
            verify_options
          )
          
          # Return the payload
          decoded_token[0]
        end
        
        # Extract user information from an ID token
        # @param decoded_token [Hash] The decoded ID token payload
        # @return [Hash] The extracted user information
        def extract_user_info(decoded_token)
          # Extract standard claims
          user_info = {}
          
          # Standard OIDC claims
          standard_claims = %i[
            sub name given_name family_name middle_name nickname preferred_username
            profile picture website email email_verified gender birthdate zoneinfo
            locale phone_number phone_number_verified address updated_at
          ]
          
          # Copy claims from token to user info
          standard_claims.each do |claim|
            user_info[claim] = decoded_token[claim] if decoded_token.key?(claim)
          end
          
          user_info
        end
        
        # Fetch the JWK Set from the jwks_url
        # @return [Hash] The JWK Set
        # @raise [ADK::Auth::ConfigurationError] If the JWK Set cannot be fetched
        def fetch_jwks
          # Check if we have a cached JWK Set and if it's still valid (cache for 1 hour)
          if @jwks_cache.any? && @jwks_cache_timestamp && (Time.now - @jwks_cache_timestamp) < 3600
            return @jwks_cache
          end
          
          # Ensure we have a JWKS URL
          unless @jwks_url
            ensure_endpoints_available
            
            unless @jwks_url
              raise ADK::Auth::ConfigurationError, 'JWKS URL not available'
            end
          end
          
          begin
            # Fetch the JWK Set
            uri = URI.parse(@jwks_url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            
            request = Net::HTTP::Get.new(uri.request_uri)
            response = http.request(request)
            
            if response.is_a?(Net::HTTPSuccess)
              # Parse the JWK Set
              @jwks_cache = JSON.parse(response.body, symbolize_names: true)
              @jwks_cache_timestamp = Time.now
              @jwks_cache
            else
              raise ADK::Auth::ConfigurationError, "JWKS request failed: #{response.code} #{response.message}"
            end
          rescue StandardError => e
            raise ADK::Auth::ConfigurationError, "Failed to fetch JWKS: #{e.message}"
          end
        end
        
        # Convert a JWK to a public key
        # @param jwk [Hash] The JWK to convert
        # @param alg [String] The algorithm
        # @return [OpenSSL::PKey::PKey] The public key
        # @raise [ADK::Auth::ConfigurationError] If the key cannot be converted
        def jwk_to_key(jwk, alg)
          begin
            case jwk[:kty]
            when 'RSA'
              # Convert an RSA JWK to a public key
              rsa_key = OpenSSL::PKey::RSA.new
              rsa_key.set_key(
                OpenSSL::BN.new(Base64.urlsafe_decode64(jwk[:n]), 2),
                OpenSSL::BN.new(Base64.urlsafe_decode64(jwk[:e]), 2),
                nil
              )
              rsa_key
            when 'EC'
              # For EC keys, convert the JWK to a public key
              # This is more complex and would require additional implementation
              raise ADK::Auth::ConfigurationError, 'EC keys are not supported yet'
            else
              raise ADK::Auth::ConfigurationError, "Unsupported key type: #{jwk[:kty]}"
            end
          rescue StandardError => e
            raise ADK::Auth::ConfigurationError, "Failed to convert JWK to key: #{e.message}"
          end
        end
      end
    end
  end
end 