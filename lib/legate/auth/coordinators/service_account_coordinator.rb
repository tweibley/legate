# frozen_string_literal: true

require_relative '../coordinator'
require_relative '../schemes/service_account'
require_relative '../config'

module Legate
  module Auth
    module Coordinators
      # ServiceAccountCoordinator handles non-interactive service account authentication
      # with automatic token exchange and refresh. Unlike OAuth2 coordinators, service
      # account authentication does not require user interaction.
      class ServiceAccountCoordinator < Coordinator
        # Authentication steps for Service Accounts
        module Steps
          TOKEN_EXCHANGE = :token_exchange
          TOKEN_REFRESH = :token_refresh
        end

        # Initialize a new Service Account coordinator
        # @param scheme [Legate::Auth::Schemes::ServiceAccount] The Service Account scheme
        # @param credential [Legate::Auth::Credential] The credential with service account information
        # @param session_service [Legate::SessionService::Base] The session service
        # @param token_store [Legate::Auth::TokenStore, nil] Optional token store
        # @param timeout [Integer, nil] Optional timeout in seconds
        def initialize(scheme:, credential:, session_service:, token_store: nil, timeout: DEFAULT_TIMEOUT)
          super(scheme: scheme, credential: credential, session_service: session_service, token_store: token_store, timeout: timeout)

          raise ArgumentError, "Expected a ServiceAccount scheme, got #{scheme.class}" unless scheme.is_a?(Legate::Auth::Schemes::ServiceAccount)

          raise ArgumentError, "Credential must have auth_type :service_account, got #{credential.auth_type}" unless credential.auth_type.to_sym == :service_account

          @current_step = Steps::TOKEN_EXCHANGE
        end

        protected

        # Implement the Service Account authentication flow
        # @return [Legate::Auth::ExchangedCredential] The authenticated credential
        # @raise [Legate::Auth::Error] If authentication fails
        def authenticate
          # Service account authentication is non-interactive, so we just exchange tokens
          @current_step = Steps::TOKEN_EXCHANGE
          exchanged_token = exchange_token

          # Store the token if we have a token store
          store_token(exchanged_token) if @token_store

          exchanged_token
        end

        # Refresh an existing token
        # @param token [Legate::Auth::ExchangedCredential] The token to refresh
        # @return [Legate::Auth::ExchangedCredential] The refreshed token
        # @raise [Legate::Auth::TokenRefreshError] If token refresh fails
        def refresh(token)
          @current_step = Steps::TOKEN_REFRESH

          # For service accounts, we get a new token rather than refreshing the existing one
          refreshed_token = @scheme.refresh_token(token, @credential)

          # Store the refreshed token if we have a token store
          store_token(refreshed_token) if @token_store

          refreshed_token
        end

        private

        # Exchange for a token
        # @return [Legate::Auth::ExchangedCredential] The exchanged token
        # @raise [Legate::Auth::TokenExchangeError] If token exchange fails
        def exchange_token
          # Create a config for token exchange, if needed by the scheme
          auth_config = Legate::Auth::Config.new(
            scheme: @scheme,
            credential: @credential,
            options: { request_id: @request_id }
          )

          # Exchange for tokens using the scheme
          # Some service account implementations might need the config, others might not
          if @scheme.method(:exchange_token).arity == 2
            @scheme.exchange_token(auth_config, @credential)
          else
            @scheme.exchange_token(@credential)
          end
        end

        # Store a token in the token store
        # @param token [Legate::Auth::ExchangedCredential] The token to store
        def store_token(token)
          return unless @token_store && token

          # Generate a key for the token
          key = generate_token_key

          # Store the token with the generated key
          @token_store.store(key, token)
        end

        # Generate a key for storing the token
        # @return [String] The generated key
        def generate_token_key
          # Create a base key using the scheme type, client email, and scopes
          base_key = "#{@scheme.scheme_type}"

          # Add client email if available
          base_key += ":#{@credential[:client_email]}" if @credential[:client_email]

          # Add scopes if available
          base_key += ":#{@scheme.scopes.join(',')}" if @scheme.scopes && !@scheme.scopes.empty?

          # Add audience if available and scopes aren't set
          base_key += ":#{@scheme.audience}" if @scheme.audience && (@scheme.scopes.nil? || @scheme.scopes.empty?)

          base_key
        end
      end
    end
  end
end
