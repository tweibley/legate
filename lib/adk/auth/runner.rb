# frozen_string_literal: true

require 'fiber'
require_relative 'error'
require_relative 'coordinator'
require_relative 'coordinators/oauth2_coordinator'
require_relative 'coordinators/oidc_coordinator'
require_relative 'coordinators/service_account_coordinator'
require_relative 'token_store'
require_relative 'token_manager'

module ADK
  module Auth
    # Runner provides the execution environment for fiber-based authentication flows.
    # It handles creating and managing authentication coordinators, running tasks within
    # a fiber, and handling authentication requests/responses.
    class Runner
      # Initialize a new authentication runner
      # @param session_service [ADK::SessionService::Base] The session service for persistence
      # @param token_store [ADK::Auth::TokenStore, nil] Optional token store for caching tokens
      # @param token_manager [ADK::Auth::TokenManager, nil] Optional token manager for lifecycle management
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
      # @raise [ADK::Auth::Error] If authentication fails
      def run(task, context = nil, &auth_handler)
        raise ArgumentError, "Task must be a Proc or lambda" unless task.is_a?(Proc)
        
        # Create a fiber for the task
        task_fiber = Fiber.new do
          begin
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
          rescue => e
            { error: e }
          end
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
        if result.is_a?(Hash) && result[:error]
          raise result[:error]
        end
        
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
              return {
                status: :completed,
                credential: result
              }
            else
              # Authentication failed
              @active_coordinators.delete(request_id)
              return {
                status: :failed,
                error: coordinator.error&.message || "Authentication failed"
              }
            end
          else
            # Authentication is still in progress, return the next request
            return {
              status: :pending,
              request: result
            }
          end
        rescue => e
          @active_coordinators.delete(request_id)
          return {
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
        
        unless coordinator
          return false
        end
        
        result = coordinator.cancel(reason)
        @active_coordinators.delete(request_id) if result
        result
      end

      private
      
      # Handle an authentication request yielded from a task fiber
      # @param request [Hash] The authentication request
      # @param task_fiber [Fiber] The task fiber
      # @yield [Hash] Optional block to handle authentication requests
      # @return [ADK::Auth::ExchangedCredential, nil] The result of authentication
      def handle_authentication_request(request, task_fiber, &auth_handler)
        scheme = request[:scheme]
        credential = request[:credential]
        options = request[:options] || {}
        
        # Validate request
        unless scheme.is_a?(ADK::Auth::Scheme)
          raise ArgumentError, "Invalid authentication scheme: #{scheme.class}"
        end
        
        unless credential.is_a?(ADK::Auth::Credential)
          raise ArgumentError, "Invalid credential: #{credential.class}"
        end
        
        # First, try to get an existing token from the token manager
        token = @token_manager.get_token(scheme, credential)
        
        # If we have a valid token, use it
        if token && !token.expired?
          return task_fiber.resume(token)
        end
        
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
            if result[:status] == :completed
              return task_fiber.resume(result[:credential])
            end
          end
        end
        
        # Otherwise, return authentication request to await client response
        { request_id: auth_request[:request_id], status: :pending }
      end
      
      # Create an appropriate coordinator based on the scheme type
      # @param scheme [ADK::Auth::Scheme] The authentication scheme
      # @param credential [ADK::Auth::Credential] The credential
      # @param options [Hash] Additional options for the coordinator
      # @return [ADK::Auth::Coordinator] The appropriate coordinator
      def create_coordinator(scheme, credential, options)
        case scheme
        when ADK::Auth::Schemes::OAuth2
          ADK::Auth::Coordinators::OAuth2Coordinator.new(
            scheme: scheme,
            credential: credential,
            session_service: @session_service,
            token_store: @token_store,
            timeout: options[:timeout],
            redirect_uri: options[:redirect_uri]
          )
        when ADK::Auth::Schemes::OIDC
          ADK::Auth::Coordinators::OIDCCoordinator.new(
            scheme: scheme,
            credential: credential,
            session_service: @session_service,
            token_store: @token_store,
            timeout: options[:timeout],
            redirect_uri: options[:redirect_uri]
          )
        when ADK::Auth::Schemes::ServiceAccount
          ADK::Auth::Coordinators::ServiceAccountCoordinator.new(
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
      # @param scheme [ADK::Auth::Schemes::ServiceAccount] The service account scheme
      # @param credential [ADK::Auth::Credential] The credential with service account info
      # @param options [Hash] Additional options for the coordinator
      # @return [ADK::Auth::Coordinators::ServiceAccountCoordinator] The coordinator
      def create_service_account_coordinator(scheme, credential, options = {})
        unless scheme.is_a?(ADK::Auth::Schemes::ServiceAccount)
          raise ArgumentError, "Expected a ServiceAccount scheme, got #{scheme.class}"
        end
        
        unless credential.auth_type.to_sym == :service_account
          raise ArgumentError, "Credential must have auth_type :service_account, got #{credential.auth_type}"
        end
        
        ADK::Auth::Coordinators::ServiceAccountCoordinator.new(
          scheme: scheme,
          credential: credential,
          session_service: @session_service,
          token_store: @token_store,
          timeout: options[:timeout]
        )
      end
      
      # Authenticate using a service account
      # @param scheme [ADK::Auth::Schemes::ServiceAccount] The service account scheme
      # @param credential [ADK::Auth::Credential] The credential with service account info
      # @param options [Hash] Additional options for the coordinator
      # @return [ADK::Auth::ExchangedCredential] The authenticated credential
      # @raise [ADK::Auth::Error] If authentication fails
      def authenticate_with_service_account(scheme, credential, options = {})
        # Create the coordinator
        coordinator = create_service_account_coordinator(scheme, credential, options)
        
        # Start the authentication flow
        coordinator.start
        
        # For service accounts, authentication is non-interactive, so the result should be available immediately
        if coordinator.complete?
          if coordinator.success?
            return coordinator.result
          else
            raise coordinator.error || ADK::Auth::Error.new("Service account authentication failed")
          end
        end
        
        # This should never happen for service accounts
        raise ADK::Auth::Error.new("Unexpected state: service account authentication requires interaction")
      end
    end
  end
end 