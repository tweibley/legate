# frozen_string_literal: true

# This file contains stubs for classes and modules needed for testing the authentication system
# These stubs allow us to test individual components without needing the full system

module Legate
  # Define Legate::Error for test stubs
  class Error < StandardError; end

  module Auth
    # Error classes for authentication
    module Errors
      class AuthenticationError < StandardError; end
      class ConfigurationError < AuthenticationError; end
      class InvalidTokenError < AuthenticationError; end
      class TokenExpiredError < AuthenticationError; end
    end

    # Credentials class for storing authentication tokens
    class Credentials
      attr_reader :access_token, :refresh_token, :token_type, :expires_in, :id_token, :scope

      def initialize(access_token: nil, refresh_token: nil, token_type: 'Bearer',
                     expires_in: nil, id_token: nil, scope: nil, **other_params)
        @access_token = access_token
        @refresh_token = refresh_token
        @token_type = token_type
        @expires_in = expires_in
        @id_token = id_token
        @scope = scope
        @other_params = other_params
      end

      def to_s
        tokens = {
          access_token: mask_token(@access_token),
          refresh_token: mask_token(@refresh_token),
          id_token: mask_token(@id_token),
          token_type: @token_type,
          expires_in: @expires_in,
          scope: @scope
        }
        tokens.select { |_, v| v }.to_s
      end

      def inspect
        to_s
      end

      def to_h
        {
          access_token: mask_token(@access_token),
          refresh_token: mask_token(@refresh_token),
          id_token: mask_token(@id_token),
          token_type: @token_type,
          expires_in: @expires_in,
          scope: @scope
        }.select { |_, v| v }
      end

      private

      def mask_token(token)
        return nil unless token
        return token if token.length < 8

        "#{token[0..3]}***#{token[-4..-1]}"
      end
    end

    # Security utilities for authentication
    module Security
      def self.generate_csrf_token
        SecureRandom.hex(16)
      end

      def self.verify_csrf_token(token, expected_token = nil)
        return false unless token

        token == if expected_token
                   expected_token
                 else
                   # For testing, verify against our static test token
                   'test_csrf_token'
                 end
      end
    end

    # Base class for authentication schemes
    class Scheme
      attr_reader :config

      def initialize(config = {})
        @config = config
      end

      def authenticate
        raise NotImplementedError, 'Subclasses must implement #authenticate'
      end
    end

    # Namespace for authentication scheme test stubs
    module TestStubs
      # API Key authentication scheme stub for testing
      class StubApiKey < Scheme
        attr_reader :name, :location, :param_name

        def initialize(name: 'api_key', location: 'header', param_name: 'X-API-Key', config: {})
          super(config)
          @name = name
          @location = location
          @param_name = param_name
        end

        def scheme_type
          :api_key
        end

        def apply_to_request(request, credential)
          api_key = credential[:api_key]
          raise Legate::Auth::Error, 'API key not found in credential' unless api_key

          case @location
          when 'header'
            request[:headers] ||= {}
            request[:headers][@param_name] = api_key
          when 'query'
            # Parse URL
            uri = URI(request[:url] || 'https://example.com')

            # Parse query params
            query_params = {}
            if uri.query
              uri.query.split('&').each do |param|
                key, value = param.split('=')
                query_params[key] = value if key && value
              end
            end

            # Add API key param
            query_params[@param_name] = api_key

            # Update URL
            uri.query = query_params.map { |k, v| "#{k}=#{v}" }.join('&')
            request[:url] = uri.to_s
          when 'cookie'
            request[:headers] ||= {}
            existing_cookies = request[:headers]['Cookie'] || ''
            new_cookie = "#{@param_name}=#{api_key}"
            request[:headers]['Cookie'] = existing_cookies.empty? ? new_cookie : "#{existing_cookies}; #{new_cookie}"
          else
            raise Legate::Auth::Error, "Invalid API key location: #{@location}"
          end

          request
        end

        def to_h
          {
            type: scheme_type,
            name: @name,
            location: @location,
            param_name: @param_name
          }
        end
      end

      # OAuth2 authentication scheme
      class OAuth2 < Scheme
        attr_reader :client_id, :client_secret, :redirect_uri, :provider_uri, :scope, :authorization_url, :token_url, :scopes, :use_pkce, :additional_params, :revocation_url

        def initialize(param = nil, **kwargs)
          # Pass the correct parameter to super with no parameters
          super()

          # Handle positional param as config hash (for backward compatibility)
          if param.is_a?(Hash)
            config = param
            @client_id = config[:client_id]
            @client_secret = config[:client_secret]
            @redirect_uri = config[:redirect_uri]
            @provider_uri = config[:provider_uri]
            @scope = config[:scope]

            # Extract values from the named parameters
            authorization_url = kwargs[:authorization_url]
            token_url = kwargs[:token_url]
            scopes = kwargs[:scopes]
            use_pkce = kwargs[:use_pkce] || true
            additional_params = kwargs[:additional_params]
            revocation_url = kwargs[:revocation_url]
          else
            # Named parameters
            authorization_url = kwargs[:authorization_url]
            token_url = kwargs[:token_url]
            scopes = kwargs[:scopes]
            use_pkce = kwargs[:use_pkce] || true
            additional_params = kwargs[:additional_params]
            revocation_url = kwargs[:revocation_url]
            config = kwargs[:config] || {}

            @client_id = config[:client_id]
            @client_secret = config[:client_secret]
            @redirect_uri = config[:redirect_uri]
            @provider_uri = config[:provider_uri]
            @scope = config[:scope]
          end
          @scopes = parse_scopes(scopes)
          @authorization_url = authorization_url
          @token_url = token_url
          @use_pkce = use_pkce
          @additional_params = additional_params
          @revocation_url = revocation_url
          @endpoints = {}
        end

        def discover_endpoints
          # In real implementation, this would make an HTTP request to discover endpoints
          # For testing, we'll return the mock endpoints
          @endpoints = {
            authorization_endpoint: "#{@provider_uri}/oauth/authorize",
            token_endpoint: "#{@provider_uri}/oauth/token",
            jwks_uri: "#{@provider_uri}/.well-known/jwks.json"
          }
        end

        def authorization_url(state: nil, **params)
          state ||= SecureRandom.hex(16)
          discover_endpoints if @endpoints.empty?

          # Use @authorization_url from initialization if provided, otherwise use endpoint
          auth_url = @authorization_url || @endpoints[:authorization_endpoint]
          return nil unless auth_url

          query_params = {
            client_id: @client_id,
            redirect_uri: @redirect_uri,
            response_type: 'code',
            state: state
          }

          # Use either @scope or @scopes
          if @scope
            query_params[:scope] = @scope
          elsif @scopes && !@scopes.empty?
            query_params[:scope] = @scopes.join(' ')
          end

          query_params.merge!(params)

          uri = URI(auth_url)
          uri.query = URI.encode_www_form(query_params)
          uri.to_s
        end

        def exchange_authorization_code(code)
          discover_endpoints if @endpoints.empty?

          # In real implementation, this would make an HTTP request
          # For testing, we'll simulate the request/response

          # This would be the actual request in a real implementation
          # response = HTTP.post(
          #   @endpoints[:token_endpoint],
          #   form: {
          #     grant_type: 'authorization_code',
          #     code: code,
          #     client_id: @client_id,
          #     client_secret: @client_secret,
          #     redirect_uri: @redirect_uri
          #   }
          # )

          # For testing, we'll use Faraday which works with WebMock
          response = Faraday.post(@endpoints[:token_endpoint]) do |req|
            req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
            req.body = URI.encode_www_form(
              grant_type: 'authorization_code',
              code: code,
              client_id: @client_id,
              client_secret: @client_secret,
              redirect_uri: @redirect_uri
            )
          end

          if response.status == 200
            JSON.parse(response.body, symbolize_names: true)

          else
            error_response = JSON.parse(response.body, symbolize_names: true)
            raise Legate::Auth::Errors::AuthenticationError, "OAuth2 token exchange failed: #{error_response[:error]}"
          end
        end

        def refresh_access_token(refresh_token)
          discover_endpoints if @endpoints.empty?

          # For testing, we'll use Faraday which works with WebMock
          response = Faraday.post(@endpoints[:token_endpoint]) do |req|
            req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
            req.body = URI.encode_www_form(
              grant_type: 'refresh_token',
              refresh_token: refresh_token,
              client_id: @client_id,
              client_secret: @client_secret
            )
          end

          if response.status == 200
            JSON.parse(response.body, symbolize_names: true)
          else
            error_response = JSON.parse(response.body, symbolize_names: true)
            raise Legate::Auth::Errors::AuthenticationError, "OAuth2 token refresh failed: #{error_response[:error]}"
          end
        end

        def client_credentials_flow
          discover_endpoints if @endpoints.empty?

          # For testing, we'll use Faraday which works with WebMock
          response = Faraday.post(@endpoints[:token_endpoint]) do |req|
            req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
            req.body = URI.encode_www_form(
              grant_type: 'client_credentials',
              client_id: @client_id,
              client_secret: @client_secret,
              scope: @scope
            )
          end

          if response.status == 200
            JSON.parse(response.body, symbolize_names: true)
          else
            error_response = JSON.parse(response.body, symbolize_names: true)
            raise Legate::Auth::Errors::AuthenticationError, "OAuth2 client credentials flow failed: #{error_response[:error]}"
          end
        end

        def verify_callback_state(state)
          Security.verify_csrf_token(state)
        end

        private

        # Parse scopes from various input formats
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

      # OpenID Connect authentication scheme
      class OpenIDConnect < OAuth2
        attr_reader :discovery_url, :userinfo_url, :jwks_url, :issuer

        def initialize(param = nil, **kwargs)
          # Call parent class initialize and pass all params
          super(param, **kwargs)

          # Extract values
          if param.is_a?(Hash)
            config = param
            discovery_url = kwargs[:discovery_url]
            jwks_url = kwargs[:jwks_url]
          else
            discovery_url = kwargs[:discovery_url]
            jwks_url = kwargs[:jwks_url]
            config = kwargs[:config] || {}
          end

          # OpenIDConnect specific fields
          @discovery_url = discovery_url
          @jwks_url = jwks_url
          @userinfo_url = nil
          @issuer = nil
        end

        def discover_endpoints
          # In a real implementation, this would use the OIDC discovery endpoint
          # For testing, we'll return mock endpoints
          @endpoints = super.merge(
            userinfo_endpoint: "#{@provider_uri}/oauth/userinfo",
            issuer: @provider_uri,
            claims_supported: %w[sub name email picture]
          )
        end

        def get_userinfo(access_token)
          discover_endpoints if @endpoints.empty?

          # Use the mock provider's userinfo endpoint instead of the OAuth endpoints
          userinfo_url = "#{@provider_uri}/userinfo"

          begin
            # In a real implementation, this would make an HTTP request
            # For testing, we'll simulate a response

            # This would be the actual request in a real implementation
            response = Faraday.get(userinfo_url) do |req|
              req.headers['Authorization'] = "Bearer #{access_token}"
            end

            raise Legate::Auth::Errors::AuthenticationError, "Failed to get user information: #{response.body}" unless response.status == 200

            JSON.parse(response.body, symbolize_names: true)
          rescue StandardError => e
            raise Legate::Auth::Errors::AuthenticationError, "Error fetching user information: #{e.message}"
          end
        end

        def verify_id_token(_id_token)
          # In a real implementation, this would validate the JWT
          # For testing, we'll just return true
          true
        end
      end

      # Service Account authentication scheme
      class ServiceAccount < Scheme
        attr_reader :client_email, :private_key, :token_url, :audience, :scopes

        def initialize(token_url:, audience: nil, scopes: nil, token_lifetime: 3600, config: {})
          super(config)
          @token_url = token_url
          @audience = audience
          @scopes = parse_scopes(scopes)
          @token_lifetime = token_lifetime
          @client_email = config[:client_email] || 'service-account@test-project.iam.gserviceaccount.com'
          @private_key = config[:private_key]
          @token = nil
          @token_expiry = 0

          validate!
        end

        def create_signed_jwt(_service_account_key = nil)
          now = Time.now.to_i

          payload = {
            iss: @client_email,
            sub: @client_email,
            aud: @token_url,
            iat: now,
            exp: now + @token_lifetime
          }

          # Add audience claim if provided
          payload[:target_audience] = @audience if @audience

          # Add scope claim if scopes are provided
          payload[:scope] = @scopes.join(' ') if @scopes&.any?

          # In a real implementation, this would sign the JWT with the private key
          # For testing, we'll just return a mock JWT
          "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.#{Base64.strict_encode64(payload.to_json)}.mock_signature"
        end

        def fetch_access_token
          # Return cached token if it's still valid
          return @token if @token && Time.now.to_i < @token_expiry

          jwt = create_signed_jwt

          # For testing, we'll use Faraday which works with WebMock
          response = Faraday.post(@token_url) do |req|
            req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
            req.body = URI.encode_www_form(
              grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
              assertion: jwt
            )
          end

          if response.status == 200
            token_data = JSON.parse(response.body, symbolize_names: true)
            @token = token_data
            @token_expiry = Time.now.to_i + token_data[:expires_in].to_i
            token_data
          else
            error_response = JSON.parse(response.body, symbolize_names: true)
            raise Legate::Auth::Errors::AuthenticationError, "Token fetch failed: #{error_response[:error]}"
          end
        end

        def authorization_header
          token = fetch_access_token
          "Bearer #{token[:access_token]}"
        end

        def make_token_request
          fetch_access_token
        end

        private

        def parse_scopes(scopes)
          return [] unless scopes
          return scopes if scopes.is_a?(Array)

          scopes.split(/\s+/)
        end

        def validate!
          raise ArgumentError, 'token_url is required' unless @token_url
        end
      end
    end

    # Namespace for authentication coordinators
    module Coordinators
      # Fiber suspension data structure
      class FiberSuspension
        attr_reader :url, :state

        def initialize(url, state)
          @url = url
          @state = state
        end
      end

      # Fiber coordinator for authentication
      class FiberCoordinator
        attr_accessor :scheme, :scheme_type, :credentials

        def initialize(config = {})
          @config = config
          @scheme = config[:scheme]

          # Normalize scheme_type to symbol, handling various input formats
          if config[:scheme_type].is_a?(String)
            @scheme_type = config[:scheme_type].downcase.to_sym
          elsif config[:scheme_type].is_a?(Symbol)
            @scheme_type = config[:scheme_type]
          elsif @scheme.respond_to?(:scheme_type)
            @scheme_type = @scheme.scheme_type
          elsif @scheme.is_a?(Class)
            @scheme_type = @scheme.name.split('::').last.downcase.to_sym
          end

          @credentials = nil
          @fiber = nil
        end

        def start
          # Create a new fiber to handle the authentication flow
          @fiber = Fiber.new do
            # Authenticate using the appropriate scheme
            authenticate
          end

          # Start the fiber and return the first yield
          @fiber.resume
        end

        def resume(response = nil)
          # Resume the fiber with the response
          @fiber.resume(response) if @fiber&.alive?
        end

        # Changed from private to public to allow direct calls in tests

        def authenticate
          # Default to oauth2 if scheme_type is nil or empty
          scheme_type = @scheme_type || :oauth2

          case scheme_type
          when :oauth2, 'oauth2'
            authenticate_oauth2
          when :openid_connect, 'openid_connect'
            authenticate_openid_connect
          when :service_account, 'service_account'
            authenticate_service_account
          else
            raise Legate::Auth::Errors::ConfigurationError, "Unsupported auth scheme type: #{scheme_type}"
          end
        end

        def refresh(credentials)
          # Default to oauth2 if scheme_type is nil or empty
          scheme_type = @scheme_type || :oauth2

          case scheme_type
          when :oauth2, :openid_connect, 'oauth2', 'openid_connect'
            refresh_oauth2(credentials)
          when :service_account, 'service_account'
            # Service accounts don't need refresh, just get a new token
            authenticate_service_account
          else
            raise Legate::Auth::Errors::ConfigurationError, "Unsupported auth scheme type for refresh: #{scheme_type}"
          end
        end

        def authenticate_oauth2
          # Generate state parameter for CSRF protection
          state = Legate::Auth::Security.generate_csrf_token

          # Initialize the scheme if it's a string
          @scheme = Legate::Auth::TestStubs::OAuth2.new(@config) if @scheme.is_a?(String)

          # Get authorization URL from the scheme
          auth_url = @scheme.authorization_url(state: state)

          # Yield to caller, which will handle the redirect
          response = Fiber.yield(Legate::Auth::Coordinators::FiberSuspension.new(auth_url, state))

          # Check for error in the response
          raise Legate::Auth::Errors::AuthenticationError, response[:error] if response[:error]

          # Exchange authorization code for tokens
          begin
            token_data = @scheme.exchange_authorization_code(response[:code])
            @credentials = Legate::Auth::Credentials.new(**token_data)
            @credentials
          rescue StandardError => e
            raise Legate::Auth::Errors::AuthenticationError, "Failed to exchange authorization code: #{e.message}"
          end
        end

        def authenticate_service_account
          # Get access token from service account
          token_response = @scheme.fetch_access_token
          @credentials = Legate::Auth::Credentials.new(**token_response)
          @credentials
        end

        def refresh_oauth2(credentials)
          # Get refresh token from credentials
          refresh_token = credentials.refresh_token

          raise Legate::Auth::Errors::AuthenticationError, 'No refresh token available' unless refresh_token

          # Initialize the scheme if it's a string
          @scheme = Legate::Auth::TestStubs::OAuth2.new(@config) if @scheme.is_a?(String)

          begin
            token_data = @scheme.refresh_access_token(refresh_token)
            @credentials = Legate::Auth::Credentials.new(**token_data)
            @credentials
          rescue StandardError => e
            raise Legate::Auth::Errors::AuthenticationError, "Failed to refresh token: #{e.message}"
          end
        end
      end
    end
  end

  # Stub session service for testing (no external dependencies)
  module SessionService
    class InMemory
      attr_reader :sessions, :scoped_states

      def initialize
        @sessions = Concurrent::Map.new
        @scoped_states = Concurrent::Map.new
        @data = {}
      end

      def set_auth_data(session_id, data)
        @data[session_id] = data
      end

      def get_auth_data(session_id)
        @data[session_id]
      end
    end
  end
end
