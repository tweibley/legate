# frozen_string_literal: true

require_relative 'error'
require_relative 'coordinator'
require_relative 'coordinators/oauth2_coordinator'
require_relative 'coordinators/oidc_coordinator'
require_relative 'coordinators/service_account_coordinator'
require_relative 'token_store'
require_relative 'token_manager'

module Legate
  module Auth
    # Runner provides the execution environment for fiber-based authentication flows.
    # It handles creating and managing authentication coordinators, running tasks within
    # a fiber, and handling authentication requests/responses.
    class Runner
      # Initialize a new authentication runner
      # @param session_service [Legate::SessionService::Base] The session service for persistence
      # @param token_store [Legate::Auth::TokenStore, nil] Optional token store for caching tokens
      # @param token_manager [Legate::Auth::TokenManager, nil] Optional token manager for lifecycle management
      def initialize(session_service:, token_store: nil, token_manager: nil)
        @session_service = session_service
        @token_store = token_store || TokenStore.new(session_service)
        @token_manager = token_manager || TokenManager.new(@token_store)
        @active_coordinators = {}
      end

      # Run a task within a fiber with authentication handling
      # @param task [Proc] The task to run
      # @param context [Object] The context to run the task in (typically ToolContext)
      # @yield [Hash, nil] Optional block to handle authentication requests
      # @return [Object] The result of the task
      # @raise [Legate::Auth::Error] If authentication fails
      def run(task, context = nil, &auth_handler)
        raise ArgumentError, 'Task must be a Proc or lambda' unless task.is_a?(Proc)

        # Create a fiber for the task
        task_fiber = Fiber.new do
          # Make the auth_session method available in the context
          if context && !context.respond_to?(:auth_session)
            context.define_singleton_method(:auth_session) do |scheme, credential, **opts|
              Fiber.yield({
                            action: :authenticate,
                            scheme: scheme,
                            credential: credential,
                            options: opts
                          })
            end
          end

          # Run the task
          task.call
        rescue StandardError => e
          { error: e }
        end

        # Start the fiber
        result = nil
        loop do
          # Resume the fiber and get the next result/yield
          result = task_fiber.resume

          # If the fiber has completed (not yielded), return the result
          break unless task_fiber.alive?

          # Handle authentication requests
          if result.is_a?(Hash) && result[:action] == :authenticate
            handle_authentication_request(result, task_fiber, &auth_handler)
          else
            # For other types of yields, just pass them to the handler if provided
            response = auth_handler ? auth_handler.call(result) : nil
            result = task_fiber.resume(response)
          end
        end

        # If the result is an error hash, raise it
        raise result[:error] if result.is_a?(Hash) && result[:error]

        result
      end

      # Handle an authentication response from the client
      # @param request_id [String] The request ID for the authentication flow
      # @param response [Hash] The response from the client
      # @return [Hash] The result of handling the response
      def handle_auth_response(request_id, response)
        coordinator = @active_coordinators[request_id]

        unless coordinator
          return {
            status: :error,
            error: "No active authentication flow found for request ID: #{request_id}"
          }
        end

        begin
          result = coordinator.resume(response)

          if coordinator.complete?
            if coordinator.success?
              # Authentication completed successfully
              @active_coordinators.delete(request_id)
              {
                status: :completed,
                credential: result
              }
            else
              # Authentication failed
              @active_coordinators.delete(request_id)
              {
                status: :failed,
                error: coordinator.error&.message || 'Authentication failed'
              }
            end
          else
            # Authentication is still in progress, return the next request
            {
              status: :pending,
              request: result
            }
          end
        rescue StandardError => e
          @active_coordinators.delete(request_id)
          {
            status: :error,
            error: "Error handling authentication response: #{e.message}"
          }
        end
      end

      # Cancel an active authentication flow
      # @param request_id [String] The request ID for the authentication flow
      # @param reason [String, nil] Optional reason for cancellation
      # @return [Boolean] True if the flow was successfully cancelled
      def cancel_auth_flow(request_id, reason = nil)
        coordinator = @active_coordinators[request_id]

        return false unless coordinator

        result = coordinator.cancel(reason)
        @active_coordinators.delete(request_id) if result
        result
      end

      private

      # Handle an authentication request yielded from a task fiber
      # @param request [Hash] The authentication request
      # @param task_fiber [Fiber] The task fiber
      # @yield [Hash] Optional block to handle authentication requests
      # @return [Legate::Auth::ExchangedCredential, nil] The result of authentication
      def handle_authentication_request(request, task_fiber, &auth_handler)
        scheme = request[:scheme]
        credential = request[:credential]
        options = request[:options] || {}

        # Validate request
        raise ArgumentError, "Invalid authentication scheme: #{scheme.class}" unless scheme.is_a?(Legate::Auth::Scheme)

        raise ArgumentError, "Invalid credential: #{credential.class}" unless credential.is_a?(Legate::Auth::Credential)

        # First, try to get an existing token from the token manager
        token = @token_manager.get_token(scheme, credential)

        # If we have a valid token, use it
        return task_fiber.resume(token) if token && !token.expired?

        # Create an appropriate coordinator based on the scheme type
        coordinator = create_coordinator(scheme, credential, options)

        # Start the authentication flow
        auth_request = coordinator.start

        # Store the coordinator for future responses
        @active_coordinators[auth_request[:request_id]] = coordinator

        # If a handler block is provided, use it
        if auth_handler
          # Pass the authentication request to the handler
          response = auth_handler.call(auth_request)

          # If the handler provided a response directly, process it
          if response
            result = handle_auth_response(auth_request[:request_id], response)

            # Return the credential to the task fiber if authentication completed
            return task_fiber.resume(result[:credential]) if result[:status] == :completed
          end
        end

        # Otherwise, return authentication request to await client response
        { request_id: auth_request[:request_id], status: :pending }
      end

      # Create an appropriate coordinator based on the scheme type
      # @param scheme [Legate::Auth::Scheme] The authentication scheme
      # @param credential [Legate::Auth::Credential] The credential
      # @param options [Hash] Additional options for the coordinator
      # @return [Legate::Auth::Coordinator] The appropriate coordinator
      def create_coordinator(scheme, credential, options)
        case scheme
        when Legate::Auth::Schemes::OAuth2
          Legate::Auth::Coordinators::OAuth2Coordinator.new(
            scheme: scheme,
            credential: credential,
            session_service: @session_service,
            token_store: @token_store,
            timeout: options[:timeout],
            redirect_uri: options[:redirect_uri]
          )
        when Legate::Auth::Schemes::OIDC
          Legate::Auth::Coordinators::OIDCCoordinator.new(
            scheme: scheme,
            credential: credential,
            session_service: @session_service,
            token_store: @token_store,
            timeout: options[:timeout],
            redirect_uri: options[:redirect_uri]
          )
        when Legate::Auth::Schemes::ServiceAccount
          Legate::Auth::Coordinators::ServiceAccountCoordinator.new(
            scheme: scheme,
            credential: credential,
            session_service: @session_service,
            token_store: @token_store,
            timeout: options[:timeout]
          )
        # Add more coordinator types as needed for other schemes
        else
          raise NotImplementedError, "No coordinator available for scheme type: #{scheme.class}"
        end
      end

      # Create a service account coordinator
      # @param scheme [Legate::Auth::Schemes::ServiceAccount] The service account scheme
      # @param credential [Legate::Auth::Credential] The credential with service account info
      # @param options [Hash] Additional options for the coordinator
      # @return [Legate::Auth::Coordinators::ServiceAccountCoordinator] The coordinator
      def create_service_account_coordinator(scheme, credential, options = {})
        raise ArgumentError, "Expected a ServiceAccount scheme, got #{scheme.class}" unless scheme.is_a?(Legate::Auth::Schemes::ServiceAccount)

        raise ArgumentError, "Credential must have auth_type :service_account, got #{credential.auth_type}" unless credential.auth_type.to_sym == :service_account

        Legate::Auth::Coordinators::ServiceAccountCoordinator.new(
          scheme: scheme,
          credential: credential,
          session_service: @session_service,
          token_store: @token_store,
          timeout: options[:timeout]
        )
      end

      # Authenticate using a service account
      # @param scheme [Legate::Auth::Schemes::ServiceAccount] The service account scheme
      # @param credential [Legate::Auth::Credential] The credential with service account info
      # @param options [Hash] Additional options for the coordinator
      # @return [Legate::Auth::ExchangedCredential] The authenticated credential
      # @raise [Legate::Auth::Error] If authentication fails
      def authenticate_with_service_account(scheme, credential, options = {})
        # Create the coordinator
        coordinator = create_service_account_coordinator(scheme, credential, options)

        # Start the authentication flow
        coordinator.start

        # For service accounts, authentication is non-interactive, so the result should be available immediately
        if coordinator.complete?
          return coordinator.result if coordinator.success?

          raise coordinator.error || Legate::Auth::Error.new('Service account authentication failed')

        end

        # This should never happen for service accounts
        raise Legate::Auth::Error.new('Unexpected state: service account authentication requires interaction')
      end
    end
  end
end
