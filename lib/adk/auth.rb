# File: lib/adk/auth.rb
# frozen_string_literal: true

require_relative 'auth/error'
require_relative 'auth/scheme'
require_relative 'auth/credential'
require_relative 'auth/config'
require_relative 'auth/exchanged_credential'
require_relative 'auth/encryption'
require_relative 'auth/token_store'
require_relative 'auth/schemes'
require_relative 'auth/coordinator'
require_relative 'auth/coordinators/oauth2_coordinator'
require_relative 'auth/coordinators/oidc_coordinator'
require_relative 'auth/coordinators/service_account_coordinator'
require_relative 'auth/excon_middleware'
require_relative 'auth/middleware_factory'
require_relative 'auth/http_client_utils'

module ADK
  # The Auth module provides authentication capabilities for ADK tools.
  # It supports various authentication schemes such as API Key, Bearer Token,
  # OAuth2, OpenID Connect, and Service Accounts.
  #
  # @example Configure a tool with authentication
  #   credential = ADK::Auth::Credential.new(
  #     auth_type: :api_key,
  #     api_key: ENV['API_KEY']
  #   )
  #
  #   scheme = ADK::Auth::Schemes::ApiKey.new(
  #     location: :header,
  #     name: 'X-API-Key'
  #   )
  #
  #   # Configure the tool with authentication
  #   tool.configure(auth: {
  #     scheme: scheme,
  #     credential: credential
  #   })
  module Auth
    # Version of the authentication module
    VERSION = '0.1.0'

    # Global mutex for access to the OAuth callback state
    @oauth_mutex = Mutex.new
    
    # Condition variable for OAuth callbacks
    @oauth_condition = ConditionVariable.new
    
    # OAuth callback response URI
    @oauth_response_uri = nil
    
    # Configuration store for Auth sessions
    @config_store = {}
    
    # Token store for credentials - initialize with a default in-memory session service
    @token_store = begin
      session_service = ADK::SessionService::InMemory.new
      TokenStore.new(session_service)
    end
    
    class << self
      # Generate a unique request ID
      # @return [String] A unique request ID
      def generate_request_id
        require 'securerandom'
        SecureRandom.uuid
      end
      
      # Apply authentication to a request
      # @param request [Hash] The request to apply authentication to
      # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential to use
      # @param scheme [ADK::Auth::Scheme, nil] The authentication scheme (if not using a stored config)
      # @return [Hash] The authenticated request
      # @raise [ADK::Auth::CredentialError] If the credential is invalid or missing required fields
      def apply_authentication(request, credential, scheme = nil)
        if credential.is_a?(ExchangedCredential) && credential.provider_id
          # Look up the scheme from the stored config
          scheme ||= get_scheme_for_provider(credential.provider_id)
        end
        
        unless scheme
          raise ADK::Auth::CredentialError, 'Authentication scheme is required'
        end
        
        # Apply the authentication to the request
        scheme.apply_to_request(request, credential)
      end
      
      # Authenticate using a coordinator
      # @param coordinator [ADK::Auth::Coordinator] The authentication coordinator
      # @return [ADK::Auth::ExchangedCredential] The authenticated credential
      # @raise [ADK::Auth::Error] If authentication fails
      def authenticate_with_coordinator(coordinator)
        # Start the authentication flow
        auth_request = coordinator.start
        
        # For non-interactive coordinators, the result might be available immediately
        if coordinator.complete?
          if coordinator.success?
            return coordinator.result
          else
            raise coordinator.error || ADK::Auth::Error.new("Authentication failed")
          end
        end
        
        # For interactive coordinators, we need to wait for user interaction
        # This method should only be used with non-interactive coordinators
        # or in testing scenarios where we can directly resume the coordinator
        raise ADK::Auth::Error.new("Coordinator requires interaction but no handler provided")
      rescue => e
        # Wrap any errors that aren't already ADK::Auth::Error
        raise e.is_a?(ADK::Auth::Error) ? e : ADK::Auth::Error.new(e.message)
      end
      
      # Start the OAuth2 authentication flow
      # @param provider_id [String] A unique identifier for the provider
      # @param scheme [ADK::Auth::Scheme] The authentication scheme
      # @param credential [ADK::Auth::Credential] The credential to use
      # @param redirect_uri [String, nil] The redirect URI for the authorization request
      # @param options [Hash, nil] Additional options for the authentication process
      # @return [String] The authorization URI to redirect the user to
      # @raise [ADK::Auth::ConfigurationError] If the configuration is invalid
      def start_oauth_flow(provider_id, scheme, credential, redirect_uri = nil, options = {})
        # Create a new config
        config = Config.new(scheme: scheme, credential: credential, options: options)
        
        # Build the authorization URI
        auth_uri = config.build_authorization_uri(redirect_uri)
        
        # Store the config
        @config_store[provider_id] = config
        
        auth_uri
      end
      
      # Handle an OAuth callback
      # @param response_uri [String] The callback URI from the OAuth provider
      # @return [Boolean] True if the callback was successfully handled
      # @raise [ADK::Auth::ConfigurationError] If the response is invalid
      def handle_oauth_callback(response_uri)
        @oauth_mutex.synchronize do
          @oauth_response_uri = response_uri
          @oauth_condition.signal
        end
        
        true
      end
      
      # Wait for the OAuth callback to be received
      # @param timeout [Integer, nil] The timeout in seconds (nil for no timeout)
      # @return [String, nil] The response URI from the OAuth provider
      def wait_for_oauth_callback(timeout = nil)
        response_uri = nil
        
        @oauth_mutex.synchronize do
          if timeout
            # Wait with timeout
            @oauth_condition.wait(@oauth_mutex, timeout) if @oauth_response_uri.nil?
          else
            # Wait indefinitely
            @oauth_condition.wait(@oauth_mutex) while @oauth_response_uri.nil?
          end
          
          response_uri = @oauth_response_uri
          @oauth_response_uri = nil
        end
        
        response_uri
      end
      
      # Exchange an authorization code for tokens
      # @param provider_id [String] The provider ID
      # @param response_uri [String] The callback URI from the OAuth provider
      # @return [ADK::Auth::ExchangedCredential] The exchanged credential with tokens
      # @raise [ADK::Auth::ConfigurationError] If the configuration is invalid
      # @raise [ADK::Auth::TokenExchangeError] If the token exchange fails
      def exchange_oauth_code(provider_id, response_uri)
        config = @config_store[provider_id]
        
        unless config
          raise ADK::Auth::ConfigurationError, "No stored configuration for provider #{provider_id}"
        end
        
        # Create a response config with the response URI
        response_config = Config.new(
          scheme: config.scheme,
          credential: config.credential,
          auth_request_id: config.auth_request_id
        )
        response_config.response_uri = response_uri
        response_config.state = config.state
        
        # Validate the response
        config.validate_response!(response_config)
        
        # Exchange the code for tokens
        exchanged_credential = config.scheme.exchange_token(response_config, config.credential)
        
        # Add the provider ID to the credential
        exchanged_credential.provider_id = provider_id
        
        # Store the credential in the token store
        @token_store.store(provider_id, exchanged_credential)
        
        exchanged_credential
      end
      
      # Get a stored exchanged credential for a provider
      # @param provider_id [String] The provider ID
      # @return [ADK::Auth::ExchangedCredential, nil] The stored credential or nil if not found
      def get_exchanged_credential(provider_id)
        @token_store.retrieve(provider_id)
      end
      
      # Complete the OAuth2 flow with a callback URI
      # @param provider_id [String] The provider ID
      # @param response_uri [String, nil] The callback URI from the OAuth provider
      # @return [ADK::Auth::ExchangedCredential] The exchanged credential with tokens
      # @raise [ADK::Auth::ConfigurationError] If the configuration is invalid
      # @raise [ADK::Auth::TokenExchangeError] If the token exchange fails
      def complete_oauth_flow(provider_id, response_uri = nil)
        # If no response URI is provided, wait for the callback
        response_uri ||= wait_for_oauth_callback
        
        unless response_uri
          raise ADK::Auth::ConfigurationError, 'No response URI provided or received'
        end
        
        # Exchange the code for tokens
        exchange_oauth_code(provider_id, response_uri)
      end
      
      # Refresh an access token
      # @param provider_id [String] The provider ID
      # @return [ADK::Auth::ExchangedCredential] The refreshed credential
      # @raise [ADK::Auth::TokenRefreshError] If the token refresh fails
      def refresh_token(provider_id)
        # Get the stored credential
        exchanged_credential = get_exchanged_credential(provider_id)
        
        unless exchanged_credential
          raise ADK::Auth::TokenRefreshError, "No stored credential for provider #{provider_id}"
        end
        
        # Get the scheme
        scheme = get_scheme_for_provider(provider_id)
        
        unless scheme && scheme.supports_refresh?
          raise ADK::Auth::TokenRefreshError, "Scheme for provider #{provider_id} does not support token refresh"
        end
        
        # Get the original credential
        config = @config_store[provider_id]
        
        unless config
          raise ADK::Auth::TokenRefreshError, "No stored configuration for provider #{provider_id}"
        end
        
        # Refresh the token
        refreshed_credential = scheme.refresh_token(exchanged_credential, config.credential)
        
        # Add the provider ID to the credential
        refreshed_credential.provider_id = provider_id
        
        # Store the refreshed credential
        @token_store.store(provider_id, refreshed_credential)
        
        refreshed_credential
      end
      
      # Get the scheme for a provider
      # @param provider_id [String] The provider ID
      # @return [ADK::Auth::Scheme, nil] The scheme or nil if not found
      private def get_scheme_for_provider(provider_id)
        config = @config_store[provider_id]
        config&.scheme
      end

      # Get the global token store instance
      # @return [ADK::Auth::TokenStore] The global token store
      def token_store
        @token_store
      end

      # Set the global token store instance
      # @param store [ADK::Auth::TokenStore] The token store to use
      # @return [ADK::Auth::TokenStore] The token store
      def token_store=(store)
        @token_store = store
      end

      # Create an authentication middleware for the specified scheme and credential
      # @param scheme [ADK::Auth::Scheme] The authentication scheme to use
      # @param credential [ADK::Auth::Credential] The credential to use
      # @param options [Hash] Additional options for the middleware
      # @return [ADK::Auth::ExconMiddleware] The configured middleware
      def create_middleware(scheme:, credential:, **options)
        ADK::Auth::MiddlewareFactory.create(
          scheme: scheme,
          credential: credential,
          token_store: options[:token_store] || token_store,
          token_manager: options[:token_manager],
          **options
        )
      end
      
      # Configure an existing Excon connection with authentication
      # @param connection [Excon::Connection] The connection to configure
      # @param scheme [ADK::Auth::Scheme] The authentication scheme to use
      # @param credential [ADK::Auth::Credential] The credential to use
      # @param options [Hash] Additional options for the middleware
      # @return [Excon::Connection] The configured connection
      def configure_connection(connection, scheme:, credential:, **options)
        ADK::Auth::HttpClientUtils.configure_connection(
          connection,
          scheme: scheme,
          credential: credential,
          token_store: options[:token_store] || token_store,
          token_manager: options[:token_manager],
          **options
        )
      end
      
      # Create a new Excon connection with authentication
      # @param url [String] The URL for the connection
      # @param scheme [ADK::Auth::Scheme] The authentication scheme to use
      # @param credential [ADK::Auth::Credential] The credential to use
      # @param options [Hash] Additional options for the connection and middleware
      # @return [Excon::Connection] The configured connection
      def create_connection(url, scheme:, credential:, **options)
        ADK::Auth::HttpClientUtils.create_connection(
          url,
          scheme: scheme,
          credential: credential,
          token_store: options[:token_store] || token_store,
          token_manager: options[:token_manager],
          **options
        )
      end
      
      # Create a new Excon connection with API key authentication
      # @param url [String] The URL for the connection
      # @param api_key [String] The API key to use
      # @param location [String] Where to place the API key ('header', 'query', 'cookie')
      # @param name [String] The name of the parameter/header
      # @param options [Hash] Additional options for the connection and middleware
      # @return [Excon::Connection] The configured connection
      def create_api_key_connection(url, api_key:, location: 'header', name: 'X-API-Key', **options)
        ADK::Auth::HttpClientUtils.create_api_key_connection(
          url,
          api_key: api_key,
          location: location,
          name: name,
          token_store: options[:token_store] || token_store,
          token_manager: options[:token_manager],
          **options
        )
      end
      
      # Create a new Excon connection with bearer token authentication
      # @param url [String] The URL for the connection
      # @param token [String] The bearer token to use
      # @param options [Hash] Additional options for the connection and middleware
      # @return [Excon::Connection] The configured connection
      def create_bearer_connection(url, token:, **options)
        ADK::Auth::HttpClientUtils.create_bearer_connection(
          url,
          token: token,
          token_store: options[:token_store] || token_store,
          token_manager: options[:token_manager],
          **options
        )
      end
      
      # Create a new Excon connection with OAuth2 authentication
      # @param url [String] The URL for the connection
      # @param client_id [String] The OAuth client ID
      # @param client_secret [String] The OAuth client secret
      # @param authorization_url [String] The authorization URL for the OAuth provider
      # @param token_url [String] The token URL for the OAuth provider
      # @param scopes [Array<String>, String, nil] The scopes to request
      # @param options [Hash] Additional options for the connection and middleware
      # @return [Excon::Connection] The configured connection
      def create_oauth2_connection(url, client_id:, client_secret:, authorization_url:, token_url:, scopes: nil, **options)
        ADK::Auth::HttpClientUtils.create_oauth2_connection(
          url,
          client_id: client_id,
          client_secret: client_secret,
          authorization_url: authorization_url,
          token_url: token_url,
          scopes: scopes,
          token_store: options[:token_store] || token_store,
          token_manager: options[:token_manager],
          **options
        )
      end
      
      # Create a new Excon connection with OpenID Connect authentication
      # @param url [String] The URL for the connection
      # @param client_id [String] The client ID to use
      # @param client_secret [String] The client secret to use
      # @param discovery_url [String] The OIDC discovery URL
      # @param options [Hash] Additional options for the connection and middleware
      # @return [Excon::Connection] The configured connection
      def create_oidc_connection(url, client_id:, client_secret:, discovery_url:, **options)
        ADK::Auth::HttpClientUtils.create_oidc_connection(
          url,
          client_id: client_id,
          client_secret: client_secret,
          discovery_url: discovery_url,
          token_store: options[:token_store] || token_store,
          token_manager: options[:token_manager],
          **options
        )
      end
      
      # Create a new Excon connection with service account authentication
      # @param url [String] The URL for the connection
      # @param service_account_key [String, Hash] The service account key as JSON string or Hash
      # @param scopes [Array<String>, String, nil] The scopes to request
      # @param audience [String, nil] The audience for the token
      # @param options [Hash] Additional options for the connection and middleware
      # @return [Excon::Connection] The configured connection
      def create_service_account_connection(url, service_account_key:, scopes: nil, audience: nil, **options)
        ADK::Auth::HttpClientUtils.create_service_account_connection(
          url, 
          service_account_key: service_account_key,
          scopes: scopes,
          audience: audience,
          token_store: options[:token_store] || token_store,
          token_manager: options[:token_manager],
          **options
        )
      end
      
      # Create a new Excon connection with Basic authentication
      # @param url [String] The URL for the connection
      # @param username [String] The username to use
      # @param password [String] The password to use
      # @param options [Hash] Additional options for the connection and middleware
      # @return [Excon::Connection] The configured connection
      def create_basic_auth_connection(url, username:, password:, **options)
        ADK::Auth::HttpClientUtils.create_basic_auth_connection(
          url,
          username: username,
          password: password,
          token_store: options[:token_store] || token_store,
          token_manager: options[:token_manager],
          **options
        )
      end
      
      # Create a new Excon connection using a previously configured provider
      # @param url [String] The URL for the connection
      # @param provider_id [String] The provider ID to use
      # @param options [Hash] Additional options for the connection and middleware
      # @return [Excon::Connection] The configured connection
      def create_connection_from_provider(url, provider_id, **options)
        ADK::Auth::HttpClientUtils.create_connection_from_provider(
          url,
          provider_id,
          token_store: options[:token_store] || token_store,
          token_manager: options[:token_manager],
          **options
        )
      end
    end
  end
end 