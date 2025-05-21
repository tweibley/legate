# File: lib/adk/auth/http_client_utils.rb
# frozen_string_literal: true

require 'excon'
require_relative 'excon_middleware'
require_relative 'middleware_factory'

module ADK
  module Auth
    # Utility module for integrating authentication with HTTP clients.
    # Provides methods for configuring Excon clients with authentication middleware.
    module HttpClientUtils
      class << self
        # Configure an Excon connection with authentication middleware
        # @param connection [Excon::Connection] The Excon connection to configure
        # @param scheme [ADK::Auth::Scheme] The authentication scheme
        # @param credential [ADK::Auth::Credential] The credential
        # @param options [Hash] Additional options for the middleware
        # @return [Excon::Connection] The configured connection
        def configure_connection(connection, scheme:, credential:, **options)
          # Create the middleware
          middleware = MiddlewareFactory.create(scheme: scheme, credential: credential, **options)
          
          # Add the middleware to the connection
          connection.data[:middlewares] ||= connection.data[:middlewares].dup
          
          # Remove any existing auth middleware of the same type
          connection.data[:middlewares].reject! { |m| m == middleware.class }
          
          # Add our middleware - ensure it's actually added to the stack
          connection.data[:middlewares] << middleware.class unless connection.data[:middlewares].include?(middleware.class)
          
          # Store the middleware instance in the connection
          connection.data[:auth_middleware] = middleware
          
          connection
        end
        
        # Create a new Excon connection with authentication middleware
        # @param url [String] The URL for the connection
        # @param scheme [ADK::Auth::Scheme] The authentication scheme
        # @param credential [ADK::Auth::Credential] The credential
        # @param options [Hash] Additional options for the Excon connection and middleware
        # @return [Excon::Connection] The configured connection
        def create_connection(url, scheme:, credential:, **options)
          # Extract middleware options from the options hash
          middleware_options = extract_middleware_options(options)
          
          # Create the connection
          connection = Excon.new(url, options)
          
          # Configure the connection with authentication
          configure_connection(connection, scheme: scheme, credential: credential, **middleware_options)
        end
        
        # Create a new Excon connection with API key authentication
        # @param url [String] The URL for the connection
        # @param api_key [String] The API key
        # @param location [String] Where to place the API key ('header', 'query', 'cookie')
        # @param name [String] The name of the parameter/header
        # @param options [Hash] Additional options for the Excon connection and middleware
        # @return [Excon::Connection] The configured connection
        def create_api_key_connection(url, api_key:, location: 'header', name: 'X-API-Key', **options)
          # Create the scheme
          scheme = ADK::Auth::Schemes::ApiKey.new
          
          # Create the credential
          credential = ADK::Auth::Credential.new(
            auth_type: :api_key,
            api_key: api_key,
            location: location,
            name: name
          )
          
          # Extract middleware options from the options hash
          middleware_options = extract_middleware_options(options)
          
          # Create the middleware using the factory
          middleware_instance = MiddlewareFactory.create(
            scheme: scheme,
            credential: credential,
            **middleware_options
          )
          
          # Prepare Excon options, ensuring we don't modify the original options hash directly
          excon_opts = options.dup
          # Remove our custom options that shouldn't be passed directly to Excon.new if they were in **options
          excon_opts.delete(:token_store) # Example, add others if necessary
          excon_opts.delete(:token_manager)
          excon_opts.delete(:session_service) # if MiddlewareFactory might add it to options
          # also retry options if they are only for our middleware and not excon directly
          [:auto_retry, :max_retries, :backoff_strategy, :backoff_factor, :retry_non_idempotent, :retry_on].each do |k|
            excon_opts.delete(k)
          end

          # Add retry configuration for Idempotent middleware
          excon_opts[:retry_limit] = 3
          excon_opts[:retry_interval] = 0.5
          excon_opts[:idempotent] = true

          # Ensure SSL verification is enabled
          excon_opts[:ssl_verify_peer] = true

          # Increase default timeouts if not specified
          excon_opts[:connect_timeout] ||= 30
          excon_opts[:read_timeout] ||= 30
          excon_opts[:write_timeout] ||= 30

          # Create the connection with our middleware
          connection = Excon.new(url, excon_opts)
          
          # Configure the middleware stack
          connection.data[:middlewares] ||= connection.data[:middlewares].dup
          connection.data[:middlewares].reject! { |m| m == ADK::Auth::ExconMiddleware }
          
          # Add our middleware class to the stack
          unless connection.data[:middlewares].include?(ADK::Auth::ExconMiddleware)
            # Find the position after Idempotent middleware
            idempotent_index = connection.data[:middlewares].index(Excon::Middleware::Idempotent)
            if idempotent_index
              connection.data[:middlewares].insert(idempotent_index + 1, ADK::Auth::ExconMiddleware)
            else
              connection.data[:middlewares] << ADK::Auth::ExconMiddleware
            end
          end
          
          # Store the middleware configuration for use by the shell instance
          connection.data[:auth_middleware_config] = middleware_instance
          
          connection
        end
        
        # Create a new Excon connection with bearer token authentication
        # @param url [String] The URL for the connection
        # @param token [String] The bearer token
        # @param options [Hash] Additional options for the Excon connection and middleware
        # @return [Excon::Connection] The configured connection
        def create_bearer_connection(url, token:, **options)
          # Extract middleware options from the options hash
          middleware_options = extract_middleware_options(options)
          
          # Create middleware using the factory
          middleware = MiddlewareFactory.create_bearer(
            token: token,
            **middleware_options
          )
          
          # Create the connection
          connection = Excon.new(url, options)
          
          # Add the middleware to the connection
          connection.data[:middlewares] ||= connection.data[:middlewares].dup
          connection.data[:middlewares].reject! { |m| m == ADK::Auth::ExconMiddleware }
          connection.data[:middlewares] << middleware.class unless connection.data[:middlewares].include?(middleware.class)
          
          # Store the middleware instance in the connection
          connection.data[:auth_middleware] = middleware
          
          connection
        end
        
        # Create a new Excon connection with OAuth2 authentication
        # @param url [String] The URL for the connection
        # @param client_id [String] The OAuth client ID
        # @param client_secret [String] The OAuth client secret
        # @param authorization_url [String] The authorization URL for the OAuth provider
        # @param token_url [String] The token URL for the OAuth provider
        # @param scopes [Array<String>, String, nil] The scopes to request
        # @param options [Hash] Additional options for the middleware and connection
        # @return [Excon::Connection] The configured connection
        def create_oauth2_connection(url, client_id:, client_secret:, authorization_url:, token_url:, scopes: nil, **options)
          # Extract middleware options from the options hash
          middleware_options = extract_middleware_options(options)
          
          # Create middleware using the factory
          middleware = MiddlewareFactory.create_oauth2(
            client_id: client_id,
            client_secret: client_secret,
            authorization_url: authorization_url,
            token_url: token_url,
            scopes: scopes,
            **middleware_options
          )
          
          # Create the connection
          connection = Excon.new(url, options)
          
          # Add the middleware to the connection
          connection.data[:middlewares] ||= connection.data[:middlewares].dup
          connection.data[:middlewares].reject! { |m| m == ADK::Auth::ExconMiddleware }
          connection.data[:middlewares] << middleware.class unless connection.data[:middlewares].include?(middleware.class)
          
          # Store the middleware instance in the connection
          connection.data[:auth_middleware] = middleware
          
          connection
        end
        
        # Create a new Excon connection with service account authentication
        # @param url [String] The URL for the connection
        # @param service_account_key [String, Hash] The service account key
        # @param scopes [Array<String>, String, nil] The scopes to request
        # @param audience [String, nil] The audience for the token
        # @param options [Hash] Additional options for the Excon connection and middleware
        # @return [Excon::Connection] The configured connection
        def create_service_account_connection(url, service_account_key:, scopes: nil, audience: nil, **options)
          # Extract middleware options from the options hash
          middleware_options = extract_middleware_options(options)
          
          # Create middleware using the factory
          middleware = MiddlewareFactory.create_service_account(
            service_account_key: service_account_key,
            scopes: scopes,
            audience: audience,
            **middleware_options
          )
          
          # Create the connection
          connection = Excon.new(url, options)
          
          # Add the middleware to the connection
          connection.data[:middlewares] ||= connection.data[:middlewares].dup
          connection.data[:middlewares].reject! { |m| m == ADK::Auth::ExconMiddleware }
          connection.data[:middlewares] << middleware.class unless connection.data[:middlewares].include?(middleware.class)
          
          # Store the middleware instance in the connection
          connection.data[:auth_middleware] = middleware
          
          connection
        end
        
        # Create a new Excon connection with OpenID Connect authentication
        # @param url [String] The URL for the connection
        # @param client_id [String] The OIDC client ID
        # @param client_secret [String] The OIDC client secret
        # @param discovery_url [String, nil] The OIDC discovery URL 
        # @param options [Hash] Additional options for the middleware and connection
        # @return [Excon::Connection] The configured connection
        def create_oidc_connection(url, client_id:, client_secret:, discovery_url:, **options)
          # Extract middleware options from the options hash
          middleware_options = extract_middleware_options(options)
          
          # Create middleware using the factory
          middleware = MiddlewareFactory.create_oidc(
            client_id: client_id,
            client_secret: client_secret,
            discovery_url: discovery_url,
            **middleware_options
          )
          
          # Create the connection
          connection = Excon.new(url, options)
          
          # Add the middleware to the connection
          connection.data[:middlewares] ||= connection.data[:middlewares].dup
          connection.data[:middlewares].reject! { |m| m == ADK::Auth::ExconMiddleware }
          connection.data[:middlewares] << middleware.class unless connection.data[:middlewares].include?(middleware.class)
          
          # Store the middleware instance in the connection
          connection.data[:auth_middleware] = middleware
          
          connection
        end
        
        # Create a new Excon connection with Basic authentication
        # @param url [String] The URL for the connection
        # @param username [String] The username
        # @param password [String] The password
        # @param options [Hash] Additional options for the middleware and connection
        # @return [Excon::Connection] The configured connection
        def create_basic_auth_connection(url, username:, password:, **options)
          # Extract middleware options from the options hash
          middleware_options = extract_middleware_options(options)
          
          # Create middleware using the factory
          middleware = MiddlewareFactory.create_basic_auth(
            username: username,
            password: password,
            **middleware_options
          )
          
          # Create the connection
          connection = Excon.new(url, options)
          
          # Add the middleware to the connection
          connection.data[:middlewares] ||= connection.data[:middlewares].dup
          connection.data[:middlewares].reject! { |m| m == ADK::Auth::ExconMiddleware }
          connection.data[:middlewares] << middleware.class unless connection.data[:middlewares].include?(middleware.class)
          
          # Store the middleware instance in the connection
          connection.data[:auth_middleware] = middleware
          
          connection
        end
        
        # Create a new Excon connection from a pre-configured authentication provider
        # @param url [String] The URL for the connection
        # @param provider_id [String] The ID of the pre-configured provider
        # @param options [Hash] Additional options for the middleware and connection
        # @return [Excon::Connection] The configured connection
        def create_connection_from_provider(url, provider_id, **options)
          # Extract middleware options from the options hash
          middleware_options = extract_middleware_options(options)
          
          # Create middleware using the factory
          middleware = MiddlewareFactory.create_from_provider(
            provider_id,
            **middleware_options
          )
          
          # Create the connection
          connection = Excon.new(url, options)
          
          # Add the middleware to the connection
          connection.data[:middlewares] ||= connection.data[:middlewares].dup
          connection.data[:middlewares].reject! { |m| m == ADK::Auth::ExconMiddleware }
          connection.data[:middlewares] << middleware.class unless connection.data[:middlewares].include?(middleware.class)
          
          # Store the middleware instance in the connection
          connection.data[:auth_middleware] = middleware
          
          connection
        end
        
        # Apply authentication to a request using the given scheme and credential
        # @param request [Hash] The request to authenticate
        # @param scheme [ADK::Auth::Scheme] The authentication scheme
        # @param credential [ADK::Auth::Credential] The credential
        # @param options [Hash] Additional options for authentication
        # @return [Hash] The authenticated request
        def authenticate_request(request, scheme:, credential:, **options)
          # Extract token store and manager from options
          token_store = options[:token_store]
          token_manager = options[:token_manager]
          
          # Apply authentication
          ToolIntegration.apply_authentication(request, scheme, credential, token_store, token_manager)
        end
        
        private
        
        # Extract middleware-specific options from a combined options hash
        # @param options [Hash] The combined options hash
        # @return [Hash] The middleware-specific options
        def extract_middleware_options(options)
          middleware_keys = [
            :token_store, :token_manager, :auto_retry, :max_retries,
            :backoff_strategy, :backoff_factor, :session_service,
            :retry_non_idempotent, :retry_on, :token_lifetime,
            :redirect_uri, :additional_params, :verify_id_token
          ]
          
          middleware_options = {}
          
          middleware_keys.each do |key|
            middleware_options[key] = options.delete(key) if options.key?(key)
          end
          
          middleware_options
        end
      end
    end
  end
end 