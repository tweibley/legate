# File: lib/adk/auth/tool_integration.rb
# frozen_string_literal: true

require_relative 'credential'
require_relative 'exchanged_credential'
require_relative 'schemes/api_key'
require_relative 'schemes/http_bearer'
require_relative 'token_manager'

module ADK
  module Auth
    # Utility module for integrating authentication with tools.
    # Provides methods for applying authentication to requests and
    # detecting authentication errors in responses.
    module ToolIntegration
      module_function

      # Apply authentication to a request based on scheme and credential
      # @param request [Hash] The request to modify
      # @param scheme [ADK::Auth::Scheme] The authentication scheme to use
      # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential to use
      # @param token_store [ADK::Auth::TokenStore, nil] Optional token store for retrieving cached tokens
      # @param token_manager [ADK::Auth::TokenManager, nil] Optional token manager for token lifecycle management
      # @return [Hash] The modified request with authentication applied
      # @raise [ADK::Auth::Error] If authentication cannot be applied
      def apply_authentication(request, scheme, credential, token_store = nil, token_manager = nil)
        raise ArgumentError, 'Request must be a Hash' unless request.is_a?(Hash)
        raise ArgumentError, 'Scheme must be an ADK::Auth::Scheme' unless scheme.is_a?(ADK::Auth::Scheme)
        
        # If we have a token manager, use it for getting tokens
        if token_manager && token_manager.is_a?(ADK::Auth::TokenManager)
          # Get a token using the token manager
          token = token_manager.get_token(scheme, credential)
          
          # Use the token if available
          credential = token if token
        # Fall back to the old mechanism if token_manager not available
        elsif token_store && credential.is_a?(ADK::Auth::Credential)
          cache_key = generate_cache_key(scheme, credential)
          exchanged_credential = token_store.get(cache_key)
          
          if exchanged_credential
            # Check if token is expired and needs refresh
            if exchanged_credential.expired? && scheme.supports_refresh?
              begin
                # Try to refresh the token
                refreshed = scheme.refresh_token(exchanged_credential, credential)
                # Store refreshed token
                token_store.store(cache_key, refreshed)
                # Use the refreshed credential
                credential = refreshed
              rescue ADK::Auth::TokenRefreshError => e
                ADK.logger.warn("Failed to refresh token: #{e.message}. Using original credential.") if defined?(ADK.logger)
                # Fall back to original credential if refresh fails
              end
            else
              # Use cached credential
              credential = exchanged_credential
            end
          end
        end
        
        # Apply the credential to the request using the scheme
        begin
          scheme.apply_to_request(request, credential)
        rescue => e
          # Log the error but return the original request to allow the request to continue
          ADK.logger.error("Error applying authentication: #{e.message}") if defined?(ADK.logger)
          request
        end
      end
      
      # Check if a response indicates an authentication error
      # @param response [Hash] The HTTP response to check
      # @return [Boolean] True if the response indicates an authentication error
      def authentication_error?(response)
        return false unless response.is_a?(Hash)
        
        # Check for common authentication error status codes
        if [401, 403].include?(response[:status])
          return true
        end
        
        # Check for common error messages in response body
        if response[:body] && response[:body].is_a?(String)
          body_lower = response[:body].downcase
          auth_error_indicators = [
            'unauthorized', 'not authorized', 'invalid token',
            'invalid api key', 'access denied', 'forbidden',
            'authentication failed'
          ]
          
          return true if auth_error_indicators.any? { |indicator| body_lower.include?(indicator) }
        end
        
        # Check for error responses with auth error messages in JSON
        if response[:body] && (response[:body].is_a?(Hash) || 
            (response[:body].is_a?(String) && response[:body].start_with?('{')))
          begin
            body = response[:body].is_a?(Hash) ? response[:body] : JSON.parse(response[:body])
            
            # Look for common error fields
            %w[error errors message].each do |field|
              next unless body[field]
              
              error_text = body[field].is_a?(String) ? body[field].downcase : body[field].to_s.downcase
              auth_error_indicators = [
                'unauthorized', 'not authorized', 'invalid token',
                'invalid api key', 'access denied', 'forbidden',
                'authentication failed'
              ]
              
              return true if auth_error_indicators.any? { |indicator| error_text.include?(indicator) }
            end
          rescue JSON::ParserError
            # Ignore parsing errors
          end
        end
        
        false
      end
      
      # Generate a cache key for storing/retrieving tokens
      # @param scheme [ADK::Auth::Scheme] The authentication scheme
      # @param credential [ADK::Auth::Credential] The credential
      # @return [String] A unique cache key
      def generate_cache_key(scheme, credential)
        # Create a hash based on scheme type and relevant credential properties
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
          parts << credential[:scope, resolve_env: false].to_s
        when :service_account
          parts << credential[:client_email, resolve_env: false].to_s
        end
        
        # Create a unique key using a digest
        require 'digest/sha2'
        "auth_#{Digest::SHA256.hexdigest(parts.join(':'))}"
      end
      
      # Determine if a request requires authentication based on URL or headers
      # @param request [Hash] The request to check
      # @return [Boolean] True if the request likely requires authentication
      def requires_authentication?(request)
        return false unless request.is_a?(Hash)
        
        # In test environments, always require authentication
        return true if request[:test_auth] == true
        
        # Check common indicators that a request requires authentication
        
        # 1. Check if path or URL contains auth-protected paths
        protected_paths = %w[
          /api/ /v1/ /v2/ /v3/ /private/ /user/ /admin/
          /account/ /secure/ /protected/ /internal/ /test/
        ]
        
        if request[:url]
          return true if protected_paths.any? { |path| request[:url].to_s.include?(path) }
        end
        
        if request[:path]
          return true if protected_paths.any? { |path| request[:path].to_s.include?(path) }
        end
        
        # 2. Check for Content-Type that often requires auth
        if request[:headers] && request[:headers]['Content-Type']
          auth_content_types = [
            'application/json', 'application/xml',
            'application/vnd.api+json'
          ]
          
          return true if auth_content_types.any? { |type| request[:headers]['Content-Type'].to_s.include?(type) }
        end
        
        # 3. Check for non-GET methods that typically require auth
        return true if request[:method] && !%w[GET HEAD OPTIONS].include?(request[:method].to_s.upcase)
        
        false
      end
    end
  end
end 