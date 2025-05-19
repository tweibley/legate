# File: lib/adk/auth/excon_middleware.rb
# frozen_string_literal: true

require 'excon'
require_relative 'tool_integration'

module ADK
  module Auth
    # Excon middleware for automatically handling authentication
    # This middleware can be inserted into the Excon middleware stack
    # to automatically apply authentication to requests and handle
    # authentication errors.
    class ExconMiddleware < Excon::Middleware::Base
      # Initialize the middleware
      # @param scheme [ADK::Auth::Scheme] The authentication scheme to use
      # @param credential [ADK::Auth::Credential] The credential to use
      # @param token_store [ADK::Auth::TokenStore, nil] Optional token store for caching tokens
      # @param auto_retry [Boolean] Whether to automatically retry on auth errors
      # @param max_retries [Integer] Maximum number of retries for auth errors
      def initialize(scheme:, credential:, token_store: nil, auto_retry: true, max_retries: 1)
        super()
        @scheme = scheme
        @credential = credential
        @token_store = token_store
        @auto_retry = auto_retry
        @max_retries = max_retries
      end

      # Called for each request in the Excon middleware stack
      # @param datum [Hash] The request/response data
      # @yield [Hash] The updated request/response data
      # @return [Hash] The request/response data
      def request_call(datum)
        if should_authenticate?(datum[:request])
          begin
            # Apply authentication to the request
            authenticated_request = ToolIntegration.apply_authentication(
              datum[:request],
              @scheme,
              @credential,
              @token_store
            )
            
            # Update the request with authentication applied
            datum[:request].merge!(authenticated_request)
          rescue => e
            ADK.logger.error("Failed to apply authentication to request: #{e.message}")
            # Continue with the request even if authentication fails
          end
        end
        
        # Continue with the middleware stack
        @stack.request_call(datum)
      end
      
      # Called after each response in the Excon middleware stack
      # @param datum [Hash] The request/response data
      # @yield [Hash] The updated request/response data
      # @return [Hash] The request/response data
      def response_call(datum)
        # Get the response from the rest of the middleware stack
        response = @stack.response_call(datum)
        
        # Check for authentication errors and handle retry if enabled
        retry_count = datum[:retry_count] || 0
        
        if @auto_retry && 
           retry_count < @max_retries && 
           ToolIntegration.authentication_error?(response)
          
          ADK.logger.warn("Authentication error detected (#{response[:status]}), retrying request")
          
          # Increment retry count
          datum[:retry_count] = retry_count + 1
          
          # Clear any cached token if we have a token store
          if @token_store && @credential.is_a?(ADK::Auth::Credential)
            cache_key = ToolIntegration.generate_cache_key(@scheme, @credential)
            @token_store.clear(cache_key)
          end
          
          # Re-authenticate and retry the request
          return request_call(datum)
        end
        
        response
      end
      
      private
      
      # Determine if a request should have authentication applied
      # @param request [Hash] The request to check
      # @return [Boolean] True if authentication should be applied
      def should_authenticate?(request)
        return false unless request
        
        # Let the ToolIntegration module determine if auth is needed
        ToolIntegration.requires_authentication?(request)
      end
    end
  end
end

# Register the middleware with Excon
Excon.defaults[:middlewares] ||= Excon.defaults[:middlewares].dup
Excon.defaults[:middlewares] << ADK::Auth::ExconMiddleware unless Excon.defaults[:middlewares].include?(ADK::Auth::ExconMiddleware) 