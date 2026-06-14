# frozen_string_literal: true

require_relative 'error'
require_relative 'config'
require_relative 'credential'
require_relative 'exchanged_credential'
require_relative 'token_store'

module Legate
  module Auth
    # Base class for authentication coordinators that handle the fiber-based authentication flow.
    # Coordinators are responsible for managing the state of an authentication flow,
    # including pausing execution, waiting for user input/authentication, and resuming
    # with appropriate credentials.
    class Coordinator
      # Default timeout for authentication flow (in seconds)
      DEFAULT_TIMEOUT = 300

      # Authentication status codes
      module Status
        PENDING = :pending
        COMPLETED = :completed
        FAILED = :failed
        TIMEOUT = :timeout
        CANCELLED = :cancelled
      end

      # Initialize a new authentication coordinator
      # @param scheme [Legate::Auth::Scheme] The authentication scheme to use
      # @param credential [Legate::Auth::Credential] The credential to use
      # @param session_service [Legate::SessionService::Base] The session service for state persistence
      # @param token_store [Legate::Auth::TokenStore, nil] Optional token store for caching tokens
      # @param timeout [Integer, nil] Optional timeout in seconds (nil for no timeout)
      def initialize(scheme:, credential:, session_service:, token_store: nil, timeout: DEFAULT_TIMEOUT)
        @scheme = scheme
        @credential = credential
        @session_service = session_service
        @token_store = token_store || TokenStore.new(session_service)
        @timeout = timeout
        @request_id = SecureRandom.uuid
        @status = Status::PENDING
        @start_time = nil
        @auth_fiber = nil
        @result = nil
        @error = nil
      end

      # Start the authentication flow
      # @return [Hash] The authentication request details to be sent to the client
      def start
        # Create a new fiber for this authentication flow
        @auth_fiber = Fiber.new do
          @start_time = Time.now
          @result = authenticate
          @status = Status::COMPLETED
        rescue Legate::Auth::Error => e
          @error = e
          @status = Status::FAILED
          nil
        rescue StandardError => e
          @error = Legate::Auth::Error.new("Unexpected error during authentication: #{e.message}", e)
          @status = Status::FAILED
          nil
        end

        # Start the fiber to get the initial authentication request
        auth_request = @auth_fiber.resume

        # Record start of authentication in session
        save_auth_state

        # Return the authentication request to be sent to the client
        {
          request_id: @request_id,
          scheme_type: @scheme.scheme_type,
          auth_request: auth_request
        }
      end

      # Resume the authentication flow with a response from the client
      # @param response [Hash] The response from the client
      # @return [Legate::Auth::ExchangedCredential, nil] The resulting credential or nil on failure
      def resume(response)
        raise Legate::Auth::Error, "Authentication flow is not in progress (status: #{@status})" unless @status == Status::PENDING

        # Check for timeout
        if @timeout && Time.now - @start_time > @timeout
          @status = Status::TIMEOUT
          @error = Legate::Auth::Error.new("Authentication timed out after #{@timeout} seconds")
          save_auth_state
          return nil
        end

        # Resume the fiber with the client response
        begin
          result = @auth_fiber.resume(response)

          # If the fiber yields again, we need more input from the client
          if @auth_fiber.alive?
            # Return the next authentication request
            return {
              request_id: @request_id,
              scheme_type: @scheme.scheme_type,
              auth_request: result
            }
          end

          # Authentication completed
          @status = Status::COMPLETED if @status == Status::PENDING
          save_auth_state

          # Store the token if we have one
          if @result && @result.is_a?(Legate::Auth::ExchangedCredential) && @token_store
            cache_key = generate_cache_key(@scheme, @credential)
            @token_store.store(cache_key, @result)
          end

          @result
        rescue StandardError => e
          @error = Legate::Auth::Error.new("Error resuming authentication: #{e.message}", e)
          @status = Status::FAILED
          save_auth_state
          nil
        end
      end

      # Cancel the authentication flow
      # @param reason [String, nil] Optional reason for cancellation
      # @return [Boolean] True if the flow was successfully cancelled
      def cancel(reason = nil)
        return false unless @status == Status::PENDING

        @status = Status::CANCELLED
        @error = Legate::Auth::Error.new("Authentication cancelled#{reason ? ": #{reason}" : ''}")
        save_auth_state
        true
      end

      # Get the current status of the authentication flow
      # @return [Symbol] The current status
      attr_reader :status

      # Get the error that occurred during authentication, if any
      # @return [Legate::Auth::Error, nil] The error or nil if no error occurred
      attr_reader :error

      # Get the result of the authentication flow
      # @return [Legate::Auth::ExchangedCredential, nil] The resulting credential or nil if not completed
      attr_reader :result

      # Check if the authentication flow is complete
      # @return [Boolean] True if the flow is complete (success or failure)
      def complete?
        @status != Status::PENDING
      end

      # Check if the authentication flow is successful
      # @return [Boolean] True if the flow completed successfully
      def success?
        @status == Status::COMPLETED && @result
      end

      protected

      # Main authentication method to be implemented by subclasses
      # This method should use Fiber.yield to pause execution and wait for client input
      # @return [Legate::Auth::ExchangedCredential] The authenticated credential
      # @raise [Legate::Auth::Error] If authentication fails
      def authenticate
        raise NotImplementedError, "Subclasses must implement the 'authenticate' method"
      end

      # Generate a cache key for the authentication token
      # @param scheme [Legate::Auth::Scheme] The authentication scheme
      # @param credential [Legate::Auth::Credential] The credential
      # @return [String] The cache key
      def generate_cache_key(scheme, credential)
        require 'digest/sha2'

        # Create a unique key based on scheme and credential
        parts = [
          scheme.scheme_type.to_s,
          credential.auth_type.to_s
        ]

        # Add scheme-specific information
        case scheme.scheme_type
        when :api_key
          parts << credential[:api_key, resolve_env: false].to_s
        when :http_bearer
          parts << credential[:bearer_token, resolve_env: false].to_s
        when :oauth2, :oidc
          parts << credential[:client_id, resolve_env: false].to_s
          parts << (credential[:scope, resolve_env: false] || '').to_s
        when :service_account
          parts << credential[:client_email, resolve_env: false].to_s
        end

        "auth_#{Digest::SHA256.hexdigest(parts.join(':'))}"
      end

      private

      # Save the current authentication state to the session
      def save_auth_state
        state = {
          request_id: @request_id,
          scheme_type: @scheme.scheme_type,
          status: @status,
          start_time: @start_time&.iso8601,
          error: @error&.message
        }

        @session_service.save_scoped_state('auth_flow', @request_id, state)
      end
    end
  end
end
