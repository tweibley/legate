# File: lib/legate/callbacks/callback_context.rb
# frozen_string_literal: true

require 'securerandom'
require_relative '../session_service/base' # For type hinting if used

module Legate
  module Callbacks
    # Context object passed to agent lifecycle and model interaction callbacks.
    class CallbackContext
      attr_reader :agent_name, :invocation_id, :session_id, :user_id, :app_name, :session_service, :logger

      # Expose pending state delta for inspection but not direct modification
      attr_reader :pending_state_delta

      # @param agent_name [Symbol]
      # @param invocation_id [String]
      # @param session_id [String]
      # @param user_id [String]
      # @param app_name [String]
      # @param session_service [Legate::SessionService::Base]
      # @param logger [Logger]
      def initialize(agent_name:, invocation_id:, session_id:, user_id:, app_name:, session_service:, logger: Legate.logger)
        @agent_name = agent_name
        @invocation_id = invocation_id
        @session_id = session_id
        @user_id = user_id
        @app_name = app_name
        @session_service = session_service
        @pending_state_delta = {} # Internal mutable hash
      end

      # Retrieves a value from the session state.
      # @param key [Symbol, String] The key to retrieve
      # @return [Object, nil] The value or nil if not found
      def state_get(key)
        Legate.logger.debug { "[CallbackContext] state_get for key: #{key} in session: #{@session_id}" }
        @session_service.get_state(session_id: @session_id, key: key)
      rescue StandardError => e
        Legate.logger.error { "[CallbackContext] Error in state_get for key '#{key}': #{e.message}" }
        nil
      end

      # Sets a value in the pending state delta. This change will be applied
      # to the session state by the Legate framework after the callback completes.
      # @param key [Symbol, String] The key to set
      # @param value [Object] The value to store (should be serializable)
      def state_set(key, value)
        Legate.logger.debug { "[CallbackContext] state_set for key: #{key} to value: #{value.inspect} (pending)" }
        @pending_state_delta[key.to_sym] = value
      end

      # Merges a hash into the pending state delta.
      # @param hash_to_merge [Hash] The hash to merge into the pending state delta
      def state_update(hash_to_merge)
        unless hash_to_merge.is_a?(Hash)
          Legate.logger.warn { "[CallbackContext] state_update called with non-hash: #{hash_to_merge.class}" }
          return
        end

        Legate.logger.debug { "[CallbackContext] state_update with hash: #{hash_to_merge.inspect} (pending)" }
        @pending_state_delta.merge!(hash_to_merge.transform_keys(&:to_sym))
      end

      # Clears any accumulated pending state changes within this context instance.
      def clear_pending_state_delta!
        @pending_state_delta = {}
      end
    end
  end
end
