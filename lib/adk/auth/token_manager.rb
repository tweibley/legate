# frozen_string_literal: true

require_relative 'token_store'
require_relative 'exchanged_credential'
require_relative 'error'

module ADK
  module Auth
    # TokenManager is responsible for managing the lifecycle of authentication tokens.
    # It provides a centralized system for token acquisition, refresh, and invalidation.
    # This class works with the TokenStore for persistence and the various authentication
    # schemes for token operations.
    class TokenManager
      # Default configuration values
      DEFAULT_CONFIG = {
        refresh_buffer: 60,       # Seconds before expiration to trigger refresh
        retry_max_attempts: 3,    # Maximum number of refresh retry attempts
        retry_delay: 2,           # Initial delay between retries (seconds)
        retry_backoff: 1.5,       # Backoff multiplier for subsequent retries
        auto_refresh: true,       # Whether to automatically refresh tokens
        background_refresh: false # Whether to refresh tokens in background
      }.freeze

      # Initialize a new TokenManager
      # @param token_store [ADK::Auth::TokenStore] The token store for persistence
      # @param config [Hash] Configuration options
      def initialize(token_store, config = {})
        @token_store = token_store
        @config = DEFAULT_CONFIG.merge(config)
        @callbacks = {
          before_expiry: [],
          refresh_success: [],
          refresh_failure: [],
          invalidated: []
        }
        @lock = Mutex.new
      end

      # Get a token for the given scheme and credential
      # @param scheme [ADK::Auth::Scheme] The authentication scheme
      # @param credential [ADK::Auth::Credential] The credential
      # @param force_refresh [Boolean] Whether to force a token refresh
      # @return [ADK::Auth::ExchangedCredential, nil] The token or nil if not available
      def get_token(scheme, credential, force_refresh: false)
        raise ArgumentError, 'Scheme must be an ADK::Auth::Scheme' unless scheme.is_a?(ADK::Auth::Scheme)

        cache_key = generate_cache_key(scheme, credential)
        
        # Use a mutex to prevent race conditions during token retrieval/refresh
        @lock.synchronize do
          # Try to get the token from the store
          token = @token_store.get(cache_key)
          
          # If no token, or force refresh, or token needs refresh, refresh it
          if force_refresh || token.nil? || needs_refresh?(token)
            return refresh_token(scheme, credential, token, cache_key)
          end
          
          # Check if token is approaching expiration and trigger callback
          if approaching_expiration?(token)
            trigger_callback(:before_expiry, token, scheme, credential)
            
            # If auto_refresh is enabled, refresh the token
            if @config[:auto_refresh]
              return refresh_token(scheme, credential, token, cache_key)
            end
          end
          
          token
        end
      end

      # Explicitly refresh a token
      # @param scheme [ADK::Auth::Scheme] The authentication scheme
      # @param credential [ADK::Auth::Credential] The credential
      # @param token [ADK::Auth::ExchangedCredential, nil] The current token, if available
      # @return [ADK::Auth::ExchangedCredential, nil] The refreshed token or nil on failure
      def refresh_token(scheme, credential, token = nil, cache_key = nil)
        raise ArgumentError, 'Scheme must be an ADK::Auth::Scheme' unless scheme.is_a?(ADK::Auth::Scheme)
        
        cache_key ||= generate_cache_key(scheme, credential)
        
        # If we don't have a token and it's an oauth or service account scheme, 
        # we need to authenticate from scratch
        if token.nil?
          if [:oauth2, :oidc, :service_account].include?(scheme.scheme_type)
            # For these schemes, we need a complete authentication flow
            # which can't be handled here - return nil to indicate need for full auth
            return nil
          end
          
          # For other schemes, we can simply apply the credential
          begin
            # Basic auth, API key, etc. - create a new token directly
            token = exchange_token(scheme, credential)
            if token
              @token_store.store(cache_key, token)
              trigger_callback(:refresh_success, token, scheme, credential)
            end
            return token
          rescue ADK::Auth::Error => e
            ADK.logger.error("Failed to create token: #{e.message}")
            trigger_callback(:refresh_failure, nil, scheme, credential, error: e)
            return nil
          end
        end
        
        # Token exists - attempt to refresh it if scheme supports refresh
        if scheme.supports_refresh? && token.refreshable?
          return perform_token_refresh(scheme, credential, token, cache_key)
        end
        
        # Scheme doesn't support refresh or token isn't refreshable
        # Return existing token if it's not expired
        return token unless token.expired?
        
        # Otherwise, invalidate it
        invalidate_token(cache_key)
        nil
      end

      # Invalidate a token, removing it from the store
      # @param cache_key [String] The cache key for the token
      # @return [Boolean] True if the token was invalidated
      def invalidate_token(cache_key)
        result = @token_store.clear(cache_key)
        trigger_callback(:invalidated, nil, nil, nil, cache_key: cache_key) if result
        result
      end

      # Revoke a token with the authentication provider
      # @param scheme [ADK::Auth::Scheme] The authentication scheme
      # @param credential [ADK::Auth::Credential] The credential
      # @param token [ADK::Auth::ExchangedCredential] The token to revoke
      # @return [Boolean] True if the token was revoked
      def revoke_token(scheme, credential, token)
        raise ArgumentError, 'Scheme must be an ADK::Auth::Scheme' unless scheme.is_a?(ADK::Auth::Scheme)
        raise ArgumentError, 'Token must be an ExchangedCredential' unless token.is_a?(ADK::Auth::ExchangedCredential)
        
        # Check if scheme supports revocation
        unless scheme.respond_to?(:revoke_token)
          ADK.logger.warn("Scheme #{scheme.scheme_type} does not support token revocation")
          return false
        end
        
        begin
          # Attempt to revoke the token
          result = scheme.revoke_token(token, credential)
          
          # Invalidate the token in our store if revocation succeeded
          if result
            cache_key = generate_cache_key(scheme, credential)
            invalidate_token(cache_key)
          end
          
          result
        rescue ADK::Auth::Error => e
          ADK.logger.error("Failed to revoke token: #{e.message}")
          false
        end
      end

      # Register a callback for token lifecycle events
      # @param event [Symbol] The event to register for (:before_expiry, :refresh_success, :refresh_failure, :invalidated)
      # @param callback [Proc] The callback to execute
      # @return [self]
      def on(event, &callback)
        unless @callbacks.key?(event)
          raise ArgumentError, "Unknown event: #{event}. Valid events: #{@callbacks.keys.join(', ')}"
        end
        
        @callbacks[event] << callback
        self
      end

      private

      # Check if a token needs to be refreshed
      # @param token [ADK::Auth::ExchangedCredential] The token to check
      # @return [Boolean] True if the token needs to be refreshed
      def needs_refresh?(token)
        token.expired?(@config[:refresh_buffer])
      end

      # Check if a token is approaching expiration
      # @param token [ADK::Auth::ExchangedCredential] The token to check
      # @return [Boolean] True if the token is approaching expiration
      def approaching_expiration?(token)
        return false unless token.expires_at
        
        # Consider a token approaching expiration if it's within 2x the refresh buffer
        buffer = @config[:refresh_buffer] * 2
        (token.expires_at - Time.now) <= buffer
      end

      # Generate a cache key for the token
      # @param scheme [ADK::Auth::Scheme] The authentication scheme
      # @param credential [ADK::Auth::Credential] The credential
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

      # Perform token refresh with retry logic
      # @param scheme [ADK::Auth::Scheme] The authentication scheme
      # @param credential [ADK::Auth::Credential] The credential
      # @param token [ADK::Auth::ExchangedCredential] The current token
      # @param cache_key [String] The cache key
      # @return [ADK::Auth::ExchangedCredential, nil] The refreshed token or nil on failure
      def perform_token_refresh(scheme, credential, token, cache_key)
        attempts = 0
        delay = @config[:retry_delay]
        
        loop do
          begin
            refreshed = scheme.refresh_token(token, credential)
            @token_store.store(cache_key, refreshed)
            trigger_callback(:refresh_success, refreshed, scheme, credential)
            return refreshed
          rescue ADK::Auth::TokenRefreshError => e
            attempts += 1
            
            # Check if we've exceeded max attempts
            if attempts >= @config[:retry_max_attempts]
              ADK.logger.error("Failed to refresh token after #{attempts} attempts: #{e.message}")
              trigger_callback(:refresh_failure, token, scheme, credential, error: e)
              return nil
            end
            
            # Wait with exponential backoff before retrying
            sleep(delay)
            delay *= @config[:retry_backoff]
          end
        end
      end

      # Exchange a credential for a token
      # @param scheme [ADK::Auth::Scheme] The authentication scheme
      # @param credential [ADK::Auth::Credential] The credential
      # @return [ADK::Auth::ExchangedCredential, nil] The exchanged token or nil on failure
      def exchange_token(scheme, credential)
        case scheme.scheme_type
        when :api_key
          # Create a simple exchanged credential for API key
          ADK::Auth::ExchangedCredential.new(
            auth_type: :api_key,
            access_token: credential[:api_key],
            token_type: 'ApiKey'
          )
        when :http_bearer
          # Create a simple exchanged credential for Bearer token
          ADK::Auth::ExchangedCredential.new(
            auth_type: :http_bearer,
            access_token: credential[:bearer_token],
            token_type: 'Bearer'
          )
        else
          # Other types like OAuth2 require a more complex flow
          # and cannot be handled directly here
          nil
        end
      end

      # Trigger a registered callback
      # @param event [Symbol] The event that occurred
      # @param token [ADK::Auth::ExchangedCredential, nil] The token involved
      # @param scheme [ADK::Auth::Scheme, nil] The authentication scheme
      # @param credential [ADK::Auth::Credential, nil] The credential
      # @param extras [Hash] Additional data to pass to the callback
      def trigger_callback(event, token, scheme, credential, extras = {})
        return unless @callbacks.key?(event)
        
        callback_data = {
          event: event,
          token: token,
          scheme: scheme,
          credential: credential
        }.merge(extras)
        
        @callbacks[event].each do |callback|
          begin
            callback.call(callback_data)
          rescue => e
            ADK.logger.error("Error in #{event} callback: #{e.message}")
          end
        end
      end
    end
  end
end 