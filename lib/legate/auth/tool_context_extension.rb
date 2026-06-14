# frozen_string_literal: true

require_relative 'runner'
require_relative 'token_manager'
require_relative 'token_store'

module Legate
  module Auth
    # Extension for Legate::ToolContext that adds fiber-based authentication support
    # This module is meant to be included in the Legate::ToolContext class to add
    # authentication-related methods for tools.
    module ToolContextExtension
      # Get or create an authentication runner for this context
      # @return [Legate::Auth::Runner] The authentication runner
      def auth_runner
        @auth_runner ||= begin
          # Create the token store
          token_store = get_token_store

          # Create a token manager
          token_manager = Legate::Auth::TokenManager.new(token_store)

          # Create the runner
          Legate::Auth::Runner.new(
            session_service: session_service,
            token_store: token_store,
            token_manager: token_manager
          )
        end
      end

      # Get a token store for this context
      # @return [Legate::Auth::TokenStore] The token store
      def get_token_store
        @token_store ||= if session_service.respond_to?(:scoped_state_container)
                           Legate::Auth::TokenStore.new(session_service)
                         elsif defined?(Legate::Auth) && Legate::Auth.respond_to?(:token_store)
                           Legate::Auth.token_store
                         else
                           Legate::Auth::TokenStore.new
                         end
      end

      # Run a block with authentication support
      # @param handler [Proc, nil] Optional handler for authentication requests
      # @yield The block to run
      # @return [Object] The result of the block
      def with_authentication(&block)
        raise ArgumentError, 'Block is required' unless block_given?

        # Get or create the authentication runner
        runner = auth_runner

        # Run the block with authentication support
        runner.run(block, self) do |auth_request|
          # Here we return nil to indicate that the auth request should be yielded
          # to the tool's caller for handling. In a real implementation, this could
          # handle authentication UI or delegate to another component.
          nil
        end
      end

      # Start an authentication session
      # @param scheme [Legate::Auth::Scheme] The authentication scheme to use
      # @param credential [Legate::Auth::Credential] The credential to use
      # @param options [Hash] Additional options for the authentication session
      # @return [Legate::Auth::ExchangedCredential] The authenticated credential
      def auth_session(scheme, credential, **options)
        # This method will be dynamically replaced by the auth_runner when
        # running in a fiber context. This implementation is just for fallback
        # when not running in a fiber.
        raise NotImplementedError, 'Authentication session not available outside of with_authentication block'
      end

      # Handle an authentication response (for tools that handle responses)
      # @param request_id [String] The request ID
      # @param response [Hash] The response
      # @return [Hash] The result of handling the response
      def handle_auth_response(request_id, response)
        runner = auth_runner
        runner.handle_auth_response(request_id, response)
      end

      # Cancel an authentication flow (for tools that handle responses)
      # @param request_id [String] The request ID
      # @param reason [String, nil] Optional reason for cancellation
      # @return [Boolean] True if the flow was successfully cancelled
      def cancel_auth_flow(request_id, reason = nil)
        runner = auth_runner
        runner.cancel_auth_flow(request_id, reason)
      end
    end
  end
end

# Extend the ToolContext class if it's already defined
Legate::ToolContext.include(Legate::Auth::ToolContextExtension) if defined?(Legate::ToolContext)
