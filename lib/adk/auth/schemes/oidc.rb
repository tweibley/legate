# frozen_string_literal: true

require_relative 'oauth2'
require 'uri'
require 'net/http'
require 'json'
require_relative '../error'
require 'base64'

module ADK
  module Auth
    module Schemes
      # OpenID Connect authentication scheme
      # This scheme extends OAuth2 with OpenID Connect specific functionality
      class OIDC < OAuth2
        # Initialize a new OIDC scheme
        # @param authorization_url [String, nil] The authorization URL (optional for non-interactive flows)
        # @param token_url [String, nil] The token URL (optional for testing)
        # @param scopes [Array<String>, String, nil] The requested scopes
        # @param discovery_url [String, nil] The OpenID Connect discovery URL
        # @param userinfo_url [String, nil] The URL for the userinfo endpoint
        # @param fetch_userinfo [Boolean] Whether to automatically fetch userinfo
        # @param client_auth_method [Symbol] The client authentication method to use
        # @param additional_params [Hash, nil] Additional parameters for authorization requests
        # @param pkce_options [Hash, nil] Options for PKCE
        def initialize(authorization_url: nil, token_url: nil, scopes: nil, discovery_url: nil,
                       userinfo_url: nil, fetch_userinfo: false, client_auth_method: :basic,
                       additional_params: nil, pkce_options: nil)
          # Call the parent constructor
          super(authorization_url: authorization_url, token_url: token_url)

          # OIDC-specific properties
          @discovery_url = discovery_url
          @userinfo_url = userinfo_url
          @fetch_userinfo = fetch_userinfo
          @pkce_options = pkce_options.is_a?(Hash) ? pkce_options : {}
        end

        # @return [Symbol] The scheme type (always :oidc)
        def scheme_type
          :oidc
        end

        # @return [String, nil] The discovery URL for the OpenID Provider
        attr_reader :discovery_url

        # @return [String, nil] The URL for the userinfo endpoint
        attr_reader :userinfo_url

        # @return [Boolean] Whether to automatically fetch userinfo
        attr_reader :fetch_userinfo

        # Check if userinfo should be fetched
        # @return [Boolean] True if userinfo should be fetched
        def should_fetch_userinfo?
          @fetch_userinfo && @userinfo_url
        end

        # Fetch user information from the userinfo endpoint
        # @param token [ADK::Auth::ExchangedCredential] The token with the access_token
        # @return [Hash] The user information
        # @raise [ADK::Auth::Error] If the userinfo request fails
        def fetch_userinfo(token)
          unless @userinfo_url
            raise ADK::Auth::Error, 'Userinfo URL not configured'
          end

          unless token&.access_token
            raise ADK::Auth::Error, 'Valid access token required to fetch userinfo'
          end

          begin
            uri = URI(@userinfo_url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == 'https')

            request = Net::HTTP::Get.new(uri.request_uri)
            request['Authorization'] = "Bearer #{token.access_token}"
            request['Accept'] = 'application/json'

            response = http.request(request)

            if response.code.to_i == 200
              JSON.parse(response.body)
            else
              raise ADK::Auth::Error, "Failed to fetch userinfo: #{response.code} - #{response.body}"
            end
          rescue JSON::ParserError => e
            raise ADK::Auth::Error, "Invalid userinfo response: #{e.message}"
          rescue => e
            raise ADK::Auth::Error, "Error fetching userinfo: #{e.message}"
          end
        end

        # Exchange an authorization code for tokens
        # @param config [ADK::Auth::Config] The authentication config
        # @param credential [ADK::Auth::Credential] The credential with client information
        # @return [ADK::Auth::ExchangedCredential] The exchanged credential with tokens
        # @raise [ADK::Auth::TokenExchangeError] If the token exchange fails
        def exchange_token(config, credential)
          # First use the parent class to exchange the token
          token = super(config, credential)

          # Optionally fetch userinfo
          if should_fetch_userinfo? && token && token.access_token
            begin
              userinfo = fetch_userinfo(token)
              # Add userinfo to the token metadata
              token = token.with(
                metadata: (token.metadata || {}).merge(userinfo: userinfo)
              )
            rescue ADK::Auth::Error => e
              ADK.logger.warn("Failed to fetch userinfo: #{e.message}")
              # Don't fail the whole flow, just log a warning
            end
          end

          token
        end

        # Exchange an authorization code for a token with ID token validation
        # @param code [String] The authorization code to exchange
        # @param credential [ADK::Auth::Credential] The credential containing client information
        # @param redirect_uri [String] The redirect URI used to obtain the code
        # @return [ADK::Auth::ExchangedCredential] The exchanged token
        # @raise [ADK::Auth::TokenExchangeError] If the code cannot be exchanged or ID token is invalid
        def exchange_code(code, credential, redirect_uri)
          # Use OAuth2 to exchange the code
          exchanged_credential = super
          
          # Additional OIDC validation
          id_token = exchanged_credential[:id_token]
          unless id_token
            raise ADK::Auth::TokenExchangeError, 'ID token not found in OIDC response'
          end
          
          # If we have a nonce in the credential, validate it against the ID token
          if credential[:nonce]
            validate_id_token_nonce(id_token, credential[:nonce])
          end
          
          # Return the validated credential
          exchanged_credential
        end

        private

        # Ensure the 'openid' scope is included in the scopes
        # @param scopes [Array<String>, String, nil] The original scopes
        # @return [Array<String>] The scopes with 'openid' included
        def ensure_openid_scope(scopes)
          case scopes
          when nil
            ['openid']
          when String
            scopes_array = scopes.split(' ')
            scopes_array.include?('openid') ? scopes : "#{scopes} openid"
          when Array
            scopes.include?('openid') ? scopes : scopes + ['openid']
          else
            ['openid']
          end
        end

        # Validate the nonce in the ID token
        # @param id_token [String] The ID token to validate
        # @param expected_nonce [String] The expected nonce value
        # @raise [ADK::Auth::TokenExchangeError] If nonce validation fails
        def validate_id_token_nonce(id_token, expected_nonce)
          # Decode the ID token (JWT)
          begin
            # Simple JWT parsing without verification (already verified by the server)
            payload = parse_jwt_payload(id_token)
            
            # Validate nonce
            if payload['nonce'] != expected_nonce
              raise ADK::Auth::TokenExchangeError, 'ID token nonce validation failed'
            end
          rescue StandardError => e
            raise ADK::Auth::TokenExchangeError, "Error validating ID token: #{e.message}"
          end
        end
        
        # Parse JWT payload without full verification
        # @param jwt [String] The JWT to parse
        # @return [Hash] The decoded payload
        def parse_jwt_payload(jwt)
          parts = jwt.split('.')
          raise 'Invalid JWT format' if parts.length != 3
          
          # Decode the payload (second part)
          begin
            json = Base64.urlsafe_decode64(padding_base64(parts[1]))
            JSON.parse(json)
          rescue StandardError => e
            raise "Failed to parse JWT payload: #{e.message}"
          end
        end
        
        # Add padding to Base64 encoded string if needed
        # @param base64_str [String] The Base64 encoded string
        # @return [String] The padded Base64 string
        def padding_base64(base64_str)
          case base64_str.length % 4
          when 0 then base64_str
          when 2 then base64_str + '=='
          when 3 then base64_str + '='
          else raise 'Invalid Base64 length'
          end
        end
      end
    end
  end
end 