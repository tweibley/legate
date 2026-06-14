# File: lib/legate/auth/middleware_factory.rb
# frozen_string_literal: true

require_relative 'excon_middleware'
require_relative 'token_store'
require_relative 'token_manager'
require_relative 'schemes/api_key'
require_relative 'schemes/http_bearer'
require_relative 'schemes/oauth2'
require_relative 'schemes/openid_connect'
require_relative 'schemes/service_account'

module Legate
  module Auth
    # Factory for creating authentication middleware instances
    # based on different scheme types and configurations.
    class MiddlewareFactory
      class << self
        # Create middleware for any authentication scheme
        # @param scheme [Legate::Auth::Scheme] The authentication scheme to use
        # @param credential [Legate::Auth::Credential] The credential to use
        # @param options [Hash] Additional options for the middleware
        # @option options [Legate::Auth::TokenStore] :token_store Optional token store for caching tokens
        # @option options [Legate::Auth::TokenManager] :token_manager Optional token manager for token lifecycle
        # @option options [Boolean] :auto_retry Whether to automatically retry on auth errors (default: true)
        # @option options [Integer] :max_retries Maximum number of retries (default: 3)
        # @option options [Symbol] :backoff_strategy Strategy for retries (:linear, :exponential, :fibonacci, :jitter, :none)
        # @option options [Float] :backoff_factor Factor to use for backoff calculation (default: 1.0)
        # @option options [Boolean] :retry_non_idempotent Whether to retry non-idempotent requests (default: false)
        # @option options [Array<Integer>] :retry_on Additional HTTP status codes to retry on
        # @return [Legate::Auth::ExconMiddleware] The configured middleware
        def create(scheme:, credential:, **options)
          # Create a token store if not provided
          token_store = options[:token_store]
          unless token_store
            session_service = options[:session_service]
            token_store = Legate::Auth::TokenStore.new(session_service) if session_service
          end

          # Create a token manager if not provided
          token_manager = options[:token_manager]

          # Configure retry options
          auto_retry = options.key?(:auto_retry) ? options[:auto_retry] : true
          max_retries = options[:max_retries] || 3
          backoff_strategy = options[:backoff_strategy] || :exponential
          backoff_factor = options[:backoff_factor] || 1.0
          retry_non_idempotent = options[:retry_non_idempotent] || false
          retry_on = options[:retry_on] || []

          # Create the middleware instance with nil stack (will be set by Excon later)
          Legate::Auth::ExconMiddleware.new(nil, {
                                              scheme: scheme,
                                              credential: credential,
                                              token_store: token_store,
                                              token_manager: token_manager,
                                              auto_retry: auto_retry,
                                              max_retries: max_retries,
                                              backoff_strategy: backoff_strategy,
                                              backoff_factor: backoff_factor,
                                              retry_non_idempotent: retry_non_idempotent,
                                              retry_on: retry_on
                                            })
        end

        # Create middleware specifically for API key authentication
        # @param api_key [String] The API key to use
        # @param location [String] Where to place the API key ('header', 'query', 'cookie')
        # @param name [String] The name of the parameter/header
        # @param options [Hash] Additional options for the middleware
        # @return [Legate::Auth::ExconMiddleware] The configured middleware
        def create_api_key(api_key:, location: 'header', name: 'X-API-Key', **options)
          # Create the scheme
          scheme = Legate::Auth::Schemes::ApiKey.new

          # Create the credential
          credential = Legate::Auth::Credential.new(
            auth_type: :api_key,
            api_key: api_key,
            location: location,
            name: name
          )

          # Create and return the middleware
          create(scheme: scheme, credential: credential, **options)
        end

        # Create middleware specifically for Bearer token authentication
        # @param token [String] The bearer token to use
        # @param options [Hash] Additional options for the middleware
        # @return [Legate::Auth::ExconMiddleware] The configured middleware
        def create_bearer(token:, **options)
          # Create the scheme
          scheme = Legate::Auth::Schemes::HTTPBearer.new

          # Create the credential
          credential = Legate::Auth::Credential.new(
            auth_type: :http_bearer,
            bearer_token: token
          )

          # Create and return the middleware
          create(scheme: scheme, credential: credential, **options)
        end

        # Create middleware specifically for OAuth2 authentication
        # @param client_id [String] The OAuth client ID
        # @param client_secret [String] The OAuth client secret
        # @param authorization_url [String] The authorization URL for the OAuth provider
        # @param token_url [String] The token URL for the OAuth provider
        # @param scopes [Array<String>, String] The OAuth scopes to request
        # @param options [Hash] Additional options for the middleware
        # @option options [String] :redirect_uri The redirect URI for the OAuth flow
        # @option options [Hash] :additional_params Additional parameters to include in the authorization request
        # @return [Legate::Auth::ExconMiddleware] The configured middleware
        def create_oauth2(client_id:, client_secret:, authorization_url:, token_url:, scopes: nil, **options)
          # Extract OAuth2-specific options
          redirect_uri = options.delete(:redirect_uri)
          additional_params = options.delete(:additional_params) || {}

          # Create the scheme with additional params
          scheme_options = {
            authorization_url: authorization_url,
            token_url: token_url,
            scopes: scopes
          }

          # Add redirect_uri if provided
          scheme_options[:redirect_uri] = redirect_uri if redirect_uri

          # Add any additional parameters
          scheme_options[:additional_params] = additional_params unless additional_params.empty?

          # Create the scheme
          scheme = Legate::Auth::Schemes::OAuth2.new(**scheme_options)

          # Create the credential
          credential = Legate::Auth::Credential.new(
            auth_type: :oauth2,
            client_id: client_id,
            client_secret: client_secret
          )

          # Create and return the middleware
          create(scheme: scheme, credential: credential, **options)
        end

        # Create middleware specifically for OpenID Connect authentication
        # @param client_id [String] The OAuth client ID
        # @param client_secret [String] The OAuth client secret
        # @param discovery_url [String, nil] The OIDC discovery URL
        # @param authorization_url [String, nil] The authorization URL (if not using discovery)
        # @param token_url [String, nil] The token URL (if not using discovery)
        # @param userinfo_url [String, nil] The userinfo URL (if not using discovery)
        # @param jwks_url [String, nil] The JWKS URL (if not using discovery)
        # @param scopes [Array<String>, String] The OAuth scopes to request
        # @param options [Hash] Additional options for the middleware
        # @option options [String] :redirect_uri The redirect URI for the OIDC flow
        # @option options [Hash] :additional_params Additional parameters to include in the authorization request
        # @option options [Boolean] :verify_id_token Whether to verify the ID token
        # @return [Legate::Auth::ExconMiddleware] The configured middleware
        def create_oidc(client_id:, client_secret:, discovery_url: nil, authorization_url: nil,
                        token_url: nil, userinfo_url: nil, jwks_url: nil, scopes: nil, **options)
          # Extract OIDC-specific options
          redirect_uri = options.delete(:redirect_uri)
          additional_params = options.delete(:additional_params) || {}
          verify_id_token = options.key?(:verify_id_token) ? options.delete(:verify_id_token) : true

          # Determine how to initialize the scheme
          scheme_options = if discovery_url
                             {
                               discovery_url: discovery_url,
                               scopes: scopes,
                               verify_id_token: verify_id_token
                             }
                           else
                             {
                               authorization_url: authorization_url,
                               token_url: token_url,
                               userinfo_url: userinfo_url,
                               jwks_url: jwks_url,
                               scopes: scopes,
                               verify_id_token: verify_id_token
                             }
                           end

          # Add redirect_uri if provided
          scheme_options[:redirect_uri] = redirect_uri if redirect_uri

          # Add any additional parameters
          scheme_options[:additional_params] = additional_params unless additional_params.empty?

          # Create the scheme
          scheme = Legate::Auth::Schemes::OIDC.new(**scheme_options)

          # Create the credential
          credential = Legate::Auth::Credential.new(
            auth_type: :oidc,
            client_id: client_id,
            client_secret: client_secret
          )

          # Create and return the middleware
          create(scheme: scheme, credential: credential, **options)
        end

        # Create middleware specifically for Service Account authentication
        # @param service_account_key [String, Hash] The service account key as JSON string or Hash
        # @param token_url [String, nil] The token URL for the service account
        # @param scopes [Array<String>, String, nil] The scopes to request
        # @param audience [String, nil] The audience for the token
        # @param options [Hash] Additional options for the middleware
        # @option options [Integer] :token_lifetime Time in seconds for token expiration (default: 3600)
        # @return [Legate::Auth::ExconMiddleware] The configured middleware
        def create_service_account(service_account_key:, token_url: nil, scopes: nil, audience: nil, **options)
          # Extract service account specific options
          token_lifetime = options.delete(:token_lifetime) || 3600

          # Parse the key if it's a string
          key_data = if service_account_key.is_a?(String)
                       begin
                         JSON.parse(service_account_key)
                       rescue JSON::ParserError
                         raise ArgumentError, 'Invalid service account key: not valid JSON'
                       end
                     else
                       service_account_key
                     end

          # Use token_url from the key if not provided
          token_url ||= key_data['token_uri']

          # Create the scheme
          scheme = Legate::Auth::Schemes::ServiceAccount.new(
            token_url: token_url,
            audience: audience,
            scopes: scopes,
            token_lifetime: token_lifetime
          )

          # Create the credential
          credential = Legate::Auth::Credential.new(
            auth_type: :service_account,
            service_account_key: service_account_key.is_a?(String) ? service_account_key : service_account_key.to_json
          )

          # Create and return the middleware
          create(scheme: scheme, credential: credential, **options)
        end

        # Create middleware specifically for Basic authentication
        # @param username [String] The username for Basic Auth
        # @param password [String] The password for Basic Auth
        # @param options [Hash] Additional options for the middleware
        # @return [Legate::Auth::ExconMiddleware] The configured middleware
        def create_basic_auth(username:, password:, **options)
          # Basic auth is handled by the HTTPBearer scheme with a different type
          scheme = Legate::Auth::Schemes::HTTPBearer.new(auth_type: :basic)

          # Create the credential
          credential = Legate::Auth::Credential.new(
            auth_type: :basic,
            username: username,
            password: password
          )

          # Create and return the middleware
          create(scheme: scheme, credential: credential, **options)
        end

        # Create middleware for a pre-configured authentication provider
        # @param provider_id [String] The ID of the pre-configured provider
        # @param options [Hash] Additional options for the middleware
        # @return [Legate::Auth::ExconMiddleware] The configured middleware
        def create_from_provider(provider_id, **options)
          # Retrieve the stored credential from Legate::Auth
          exchanged_credential = Legate::Auth.get_exchanged_credential(provider_id)
          raise ArgumentError, "No credential found for provider ID: #{provider_id}" unless exchanged_credential

          # Get the scheme
          scheme = Legate::Auth.get_scheme_for_provider(provider_id)
          raise ArgumentError, "No scheme found for provider ID: #{provider_id}" unless scheme

          # Create and return the middleware
          create(scheme: scheme, credential: exchanged_credential, **options)
        end
      end
    end
  end
end
