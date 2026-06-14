# File: lib/legate/auth/token_store.rb
# frozen_string_literal: true

require_relative 'exchanged_credential'

module Legate
  module Auth
    # Provides a token store for caching authentication tokens
    # This class wraps a session service and provides methods
    # for storing, retrieving, and clearing tokens
    class TokenStore
      # Initialize a new token store
      # @param session_service [Legate::SessionService::Base] The session service to use
      def initialize(session_service)
        @session_service = session_service
        @scope = 'auth' # Scoped state namespace for authentication
      end

      # Store a token in the cache
      # @param key [String] The cache key
      # @param token [Legate::Auth::ExchangedCredential] The token to store
      # @return [Boolean] True if the token was stored
      def store(key, token)
        return false unless token.is_a?(Legate::Auth::ExchangedCredential)

        begin
          # Serialize token to hash
          token_data = token.to_h

          # Store in scoped state
          @session_service.save_scoped_state(@scope, key, token_data)
          true
        rescue StandardError => e
          Legate.logger.error("Failed to store token: #{e.message}")
          false
        end
      end

      # Get a token from the cache
      # @param key [String] The cache key
      # @return [Legate::Auth::ExchangedCredential, nil] The token or nil if not found or expired
      def get(key)
        # Retrieve from scoped state
        token_data = @session_service.load_scoped_state(@scope, key)
        return nil unless token_data

        # Deserialize to token object
        token = Legate::Auth::ExchangedCredential.from_h(token_data)

        # Check expiration
        if token.expired?
          Legate.logger.debug("Retrieved expired token from cache (key: #{key})")
          # Clear expired token
          clear(key)
          return nil
        end

        token
      rescue StandardError => e
        Legate.logger.error("Failed to retrieve token: #{e.message}")
        nil
      end

      # Clear a token from the cache
      # @param key [String] The cache key to clear
      # @return [Boolean] True if the token was cleared
      def clear(key)
        @session_service.clear_scoped_state(@scope, key)
        true
      rescue StandardError => e
        Legate.logger.error("Failed to clear token: #{e.message}")
        false
      end

      # Clear all tokens from the cache
      # @return [Boolean] True if all tokens were cleared
      def clear_all
        @session_service.clear_scoped_state(@scope, '*')
        true
      rescue StandardError => e
        Legate.logger.error("Failed to clear all tokens: #{e.message}")
        false
      end
    end
  end
end
