# frozen_string_literal: true

require_relative '../coordinator'
require_relative '../schemes/oauth2'
require_relative '../config'

module Legate
  module Auth
    module Coordinators
      # OAuth2Coordinator handles the interactive OAuth2 authentication flow using fibers.
      # It manages pausing execution to request user authorization, and resuming once
      # the authorization code is received.
      class OAuth2Coordinator < Coordinator
        # Authentication steps for OAuth2
        module Steps
          AUTHORIZATION = :authorization
          TOKEN_EXCHANGE = :token_exchange
        end

        # Initialize a new OAuth2 coordinator
        # @param scheme [Legate::Auth::Schemes::OAuth2] The OAuth2 scheme
        # @param credential [Legate::Auth::Credential] The credential with client information
        # @param session_service [Legate::SessionService::Base] The session service
        # @param token_store [Legate::Auth::TokenStore, nil] Optional token store
        # @param timeout [Integer, nil] Optional timeout in seconds
        # @param redirect_uri [String, nil] Optional redirect URI
        def initialize(scheme:, credential:, session_service:, token_store: nil, timeout: DEFAULT_TIMEOUT, redirect_uri: nil)
          super(scheme: scheme, credential: credential, session_service: session_service, token_store: token_store, timeout: timeout)

          raise ArgumentError, "Expected an OAuth2 scheme, got #{scheme.class}" unless scheme.is_a?(Legate::Auth::Schemes::OAuth2)

          raise ArgumentError, "Credential must have auth_type :oauth2, got #{credential.auth_type}" unless credential.auth_type == :oauth2

          @redirect_uri = redirect_uri
          @current_step = Steps::AUTHORIZATION
          @auth_config = nil
        end

        protected

        # Implement the OAuth2 authentication flow
        # @return [Legate::Auth::ExchangedCredential] The authenticated credential
        # @raise [Legate::Auth::Error] If authentication fails
        def authenticate
          # Step 1: Create authorization request
          @current_step = Steps::AUTHORIZATION
          authorization_response = request_authorization

          # Step 2: Exchange code for tokens
          @current_step = Steps::TOKEN_EXCHANGE
          exchange_code_for_token(authorization_response)
        end

        private

        # Request authorization from the user
        # @return [Hash] The authorization response from the client
        def request_authorization
          # Create a config for the authorization request
          @auth_config = Legate::Auth::Config.new(
            scheme: @scheme,
            credential: @credential,
            options: { request_id: @request_id }
          )

          # Build the authorization URI
          authorization_uri = @auth_config.build_authorization_uri(@redirect_uri)

          # Yield to pause execution and wait for authorization response
          response = Fiber.yield({
                                   type: 'authorization_request',
                                   authorization_url: authorization_uri[:uri],
                                   state: authorization_uri[:state],
                                   redirect_uri: @redirect_uri
                                 })

          # Validate the response
          raise Legate::Auth::Error, "Invalid authorization response: expected Hash, got #{response.class}" unless response.is_a?(Hash)

          raise Legate::Auth::Error, 'Missing response_uri in authorization response' unless response['response_uri']

          response
        end

        # Exchange the authorization code for tokens
        # @param authorization_response [Hash] The authorization response from the client
        # @return [Legate::Auth::ExchangedCredential] The authenticated credential
        # @raise [Legate::Auth::TokenExchangeError] If token exchange fails
        def exchange_code_for_token(authorization_response)
          # Update the config with the response URI
          @auth_config.response_uri = authorization_response['response_uri']

          # Exchange the code for tokens
          @scheme.exchange_token(@auth_config, @credential)
        end
      end
    end
  end
end
