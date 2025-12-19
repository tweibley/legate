# File: lib/adk/session_service/redis.rb
# frozen_string_literal: true

require 'redis'
require 'json'
require 'time' # For iso8601 parsing
require_relative '../session'
require_relative '../event'
require_relative 'base'
require_relative '../auth/encryption' # Added for encryption support

module ADK
  module SessionService
    # Stores sessions in Redis for persistence and provides optimistic locking mechanisms for concurrent access.
    #
    # ## Storage Structure
    # - Uses Redis Hash structures for session metadata and state
    # - Uses Redis Lists for storing events in each session
    # - Uses Redis Sets to index and track all sessions
    #
    # ## Concurrency Handling
    # This implementation uses Redis' WATCH/MULTI/EXEC pattern for optimistic locking to safely
    # handle concurrent modifications, particularly when dealing with state delta merges. This
    # ensures that state modifications are atomic and race conditions are properly handled.
    #
    # ## State Management
    # When events with state deltas are processed, the implementation:
    # 1. Fetches the current state atomically
    # 2. Merges the state delta onto the current state
    # 3. Uses optimistic locking to ensure the state hasn't changed during the operation
    # 4. Retries the operation on conflicts up to a configured maximum
    #
    # ## Security
    # Sensitive credential data is encrypted before storage in Redis using the ADK::Auth::Encryption
    # module, which provides authenticated encryption via rbnacl. The encryption key is configured
    # through an environment variable.
    class Redis < Base
      # Key Definitions
      REDIS_SESSION_HASH_PREFIX = 'adk:session:'
      REDIS_SESSION_EVENTS_LIST_PREFIX = 'adk:session:events:'
      REDIS_SESSIONS_SET_KEY = 'adk:sessions:all_ids'
      REDIS_SCOPED_STATE_PREFIX = 'adk:state:'

      # Authentication-specific data namespace in session state
      AUTH_TOKEN_CACHE_KEY = :auth_token_cache

      # Sensitive fields that should always be encrypted
      SENSITIVE_FIELDS = [
        AUTH_TOKEN_CACHE_KEY,
        :credentials,
        :tokens,
        :api_keys,
        :passwords,
        :secrets
      ].freeze

      # Default TTL for session keys (in seconds). Set to nil or 0 for no expiry.
      # Example: 7 days = 7 * 24 * 60 * 60 = 604800
      DEFAULT_SESSION_TTL = 604_800

      # Maximum number of retry attempts for optimistic locking operations
      # When WATCH detects a conflict, the operation will retry this many times
      DEFAULT_MAX_RETRIES = 3

      attr_reader :redis_client, :session_ttl, :encryption_enabled

      # Initializes the service with a Redis client.
      # @param redis_client [Redis] An active Redis client instance.
      # @param session_ttl [Integer, nil] TTL for session keys in seconds (nil for no expiry).
      # @param enable_encryption [Boolean] Whether to enable encryption for sensitive data.
      def initialize(redis_client: nil, session_ttl: DEFAULT_SESSION_TTL, enable_encryption: true)
        @redis_client = redis_client || connect_redis
        @session_ttl = session_ttl
        @encryption_enabled = enable_encryption

        if @encryption_enabled
          # Check if encryption is possible
          begin
            ADK::Auth::Encryption.encrypt('test')
            ADK.logger.info("RedisSessionService initialized with encryption. Session TTL: #{session_ttl || 'None'}")
          rescue StandardError => e
            ADK.logger.warn("Encryption requested but unavailable: #{e.message}. Falling back to unencrypted mode.")
            @encryption_enabled = false
          end
        end

        ADK.logger.info("RedisSessionService initialized. Encryption: #{@encryption_enabled}, Session TTL: #{session_ttl || 'None'}")
      end

      # Creates a new session and stores it in Redis.
      #
      # This operation is performed as an atomic transaction using Redis MULTI/EXEC to ensure
      # that all related operations succeed or fail together:
      # 1. Store session metadata and state in a hash
      # 2. Add session ID to the global set
      # 3. Set TTL on the session and events keys if configured
      #
      # @param app_name [String] Identifier for the agent application.
      # @param user_id [String] Identifier for the user initiating the session.
      # @param initial_state [Hash] Optional initial data for the session state.
      # @return [ADK::Session] The newly created session object.
      # @raise [ADK::Error] If the session could not be created in Redis.
      def create_session(app_name:, user_id:, initial_state: {})
        # Initialize an auth_token_cache in the initial state if not present
        secure_initial_state = initial_state.dup
        secure_initial_state[AUTH_TOKEN_CACHE_KEY] ||= {}

        session = ADK::Session.new(
          app_name: app_name,
          user_id: user_id,
          initial_state: secure_initial_state,
          session_service: self
        )
        session_key = redis_session_key(session.id)
        events_key = redis_events_key(session.id)

        begin
          # Process state for storage, applying encryption to sensitive fields
          processed_state = process_state_for_storage(session.state_to_h)
          state_json = JSON.generate(processed_state)

          session_data = {
            app_name: session.app_name,
            user_id: session.user_id,
            created_at: session.created_at.iso8601(3),
            updated_at: session.updated_at.iso8601(3),
            state: state_json
          }

          # Execute creation as a Redis transaction to ensure atomicity
          results = @redis_client.multi do |multi|
            multi.hset(session_key, session_data)
            multi.sadd(REDIS_SESSIONS_SET_KEY, session.id)
            # Optionally set TTL if configured
            if @session_ttl&.positive?
              multi.expire(session_key, @session_ttl)
              # Only set TTL on events list if it exists
              multi.expire(events_key, @session_ttl) if @redis_client.exists?(events_key)
            end
          end

          # Basic check on multi results (can be more specific if needed)
          unless results.all?
            ADK.logger.error("Redis MULTI command failed during session creation for ID: #{session.id}. Results: #{results.inspect}")
            # Consider cleanup or raising an error
            raise ADK::Error, 'Failed to create session in Redis.'
          end

          ADK.logger.info("Created session in Redis: #{session.id} for app:#{app_name}, user:#{user_id}")
          session
        rescue JSON::GeneratorError => e
          ADK.logger.error("Failed to serialize session state for #{session.id}: #{e.message}")
          raise ADK::Error, 'Failed to serialize session state.'
        rescue ::Redis::BaseError => e
          ADK.logger.error("Redis error creating session #{session.id}: #{e.class} - #{e.message}")
          raise ADK::Error, 'Redis error during session creation.'
        end
      end

      # Retrieves a session from Redis by its ID.
      #
      # Uses Redis pipelining to fetch both the session hash and event list in a single
      # network round-trip for improved performance, though note this is not a transaction.
      #
      # @param session_id [String] The unique ID of the session to retrieve.
      # @return [ADK::Session, nil] The session object if found, otherwise nil.
      # @raise [ADK::Error] If a Redis error occurs during retrieval.
      def get_session(session_id:)
        session_key = redis_session_key(session_id)
        events_key = redis_events_key(session_id)

        begin
          # Fetch session hash and events list atomically if possible (pipelined)
          results = @redis_client.pipelined do |pipe|
            pipe.hgetall(session_key)
            pipe.lrange(events_key, 0, -1)
          end

          session_hash_data = results[0]
          event_json_list = results[1]

          # Check if session hash exists - return nil if not found
          if session_hash_data.nil? || session_hash_data.empty?
            ADK.logger.debug("Session not found in Redis: #{session_id}")
            return nil
          end

          # Deserialize session state
          state = {}
          if session_hash_data['state']
            begin
              encrypted_state = JSON.parse(session_hash_data['state'], symbolize_names: true)
              # Process state from storage, decrypting any encrypted fields
              state = process_state_from_storage(encrypted_state)
            rescue JSON::ParserError => e
              ADK.logger.error("Failed to parse state JSON for session #{session_id}: #{e.message}. Data: #{session_hash_data['state']}")
              state = { _parse_error: "Failed to load state: #{e.message}" } # Include error in state
            end
          end

          # Deserialize events
          events = []
          event_json_list&.each_with_index do |event_json, index|
            event_hash = JSON.parse(event_json, symbolize_names: true)
            event = ADK::Event.from_h(event_hash)
            events << event if event # from_h returns nil on error
          rescue JSON::ParserError => e
            ADK.logger.error("Failed to parse event JSON at index #{index} for session #{session_id}: #{e.message}. Data: #{event_json}")
            # Optionally add a placeholder event? Or just skip. Skipping for now.
          end

          # Reconstruct Session object
          # Manually build hash for Session.new to match its expected keys
          session_data_for_init = {
            id: session_id,
            app_name: session_hash_data['app_name'],
            user_id: session_hash_data['user_id'],
            initial_state: state, # Pass parsed state
            events: events, # Pass parsed events
            session_service: self
          }
          session = ADK::Session.new(**session_data_for_init)

          # Manually set timestamps after initialization from stored values
          if session_hash_data['created_at']
            session.instance_variable_set(:@created_at,
                                          Time.iso8601(session_hash_data['created_at']))
          end
          if session_hash_data['updated_at']
            session.instance_variable_set(:@updated_at,
                                          Time.iso8601(session_hash_data['updated_at']))
          end

          ADK.logger.debug("Retrieved session from Redis: #{session_id}")
          session
        rescue ::Redis::BaseError => e
          ADK.logger.error("Redis error getting session #{session_id}: #{e.class} - #{e.message}")
          raise ADK::Error, 'Redis error during session retrieval.'
        rescue ArgumentError, TypeError => e # Catch potential errors in Time.iso8601 or Session init
          ADK.logger.error("Error reconstructing session object for #{session_id}: #{e.class} - #{e.message}")
          nil # Return nil if reconstruction fails
        end
      end

      # Appends an event to a session's event list and updates the state and timestamp in Redis.
      #
      # ## Optimistic Locking Implementation
      # This method implements optimistic locking using Redis' WATCH/MULTI/EXEC pattern:
      #
      # 1. WATCH the session key to detect concurrent modifications
      # 2. Fetch the current state if the event has a state_delta
      # 3. Merge the state delta with the current state
      # 4. Execute a transaction (MULTI/EXEC) to update all related data atomically
      # 5. If WATCH detects a conflict (another client modified the data), retry the operation
      #
      # The method will retry up to max_retries times (default: 3) if conflicts are detected,
      # making it resilient to high-concurrency scenarios while avoiding race conditions.
      #
      # ## State Delta Handling
      # If the event contains a state_delta, we:
      # 1. Fetch the current state within the WATCH block
      # 2. Merge the state delta with the current state
      # 3. Apply the merged state in the transaction
      #
      # This ensures that concurrent state modifications don't overwrite each other.
      #
      # @param session_id [String] The ID of the session to update.
      # @param event [ADK::Event] The event to append. Must be an instance of ADK::Event.
      # @return [Boolean] True if successful, false otherwise (e.g., session not found, invalid event, Redis error, WATCH conflict).
      def append_event(session_id:, event:)
        return false unless event.is_a?(ADK::Event)

        session_key = redis_session_key(session_id)
        events_key = redis_events_key(session_id)

        # Check if session exists
        return false unless @redis_client.exists?(session_key)

        # Get the session
        session = get_session(session_id: session_id)
        return false unless session

        # Add the event to the session
        added_event = session.add_event(event)
        return false unless added_event

        # Maximum number of retries for optimistic locking
        max_retries = DEFAULT_MAX_RETRIES
        retries = 0

        begin
          loop do
            # WATCH the session key to detect concurrent modifications
            # If another client modifies the key between WATCH and EXEC,
            # the transaction will fail and return nil
            @redis_client.watch(session_key) do
              # If event has state_delta, fetch current state
              # This must be done within the WATCH block to ensure we have
              # the latest state before modifying it
              if event.state_delta && !event.state_delta.empty?
                current_state_json = @redis_client.hget(session_key, 'state')
                if current_state_json
                  begin
                    encrypted_state = JSON.parse(current_state_json, symbolize_names: true)
                    current_state = process_state_from_storage(encrypted_state)
                    # Merge state delta with current state to preserve other modifications
                    session.update_state(current_state.merge(event.state_delta))
                  rescue JSON::ParserError => e
                    ADK.logger.error("Failed to parse current state JSON for session #{session_id}: #{e.message}")
                    return false
                  end
                end
              end

              # Execute a Redis transaction to atomically update all related data
              # All commands will be queued and executed as a single atomic unit
              results = @redis_client.multi do |multi|
                # Add event to the events list
                multi.rpush(events_key, JSON.generate(added_event.to_h))

                # Update session hash with new state and timestamp
                multi.hset(session_key, 'updated_at', session.updated_at.iso8601(3))

                # Only update state if it changed
                if event.state_delta && !event.state_delta.empty?
                  # Process state for storage, encrypting sensitive data
                  processed_state = process_state_for_storage(session.state_to_h)
                  multi.hset(session_key, 'state', JSON.generate(processed_state))
                end

                # Refresh TTL if configured
                if @session_ttl&.positive?
                  multi.expire(session_key, @session_ttl)
                  multi.expire(events_key, @session_ttl)
                end
              end

              # Check if transaction was successful
              # If nil, it means the WATCH detected a concurrent modification
              if results.nil?
                # Watch failed, retry if we haven't exceeded max retries
                retries += 1
                if retries >= max_retries
                  ADK.logger.warn("Max retries (#{max_retries}) exceeded for session #{session_id} event append")
                  return false
                end
                next # Continue to the next iteration of the loop to retry
              end

              # Check if all commands in the transaction succeeded
              unless results.all?
                ADK.logger.error("Redis MULTI command failed during event append for session #{session_id}. Results: #{results.inspect}")
                return false
              end

              ADK.logger.debug("Appended event to session #{session_id}: #{event.role} - #{event.content}")
              return true
            end
          end
        rescue ::Redis::BaseError => e
          ADK.logger.error("Redis error appending event to session #{session_id}: #{e.class} - #{e.message}")
          begin
            @redis_client.unwatch
          rescue StandardError
            nil
          end # Best effort to unwatch
          false
        end
      end

      # Deletes a session and its associated events list from Redis.
      #
      # Executes the deletion as an atomic transaction using Redis MULTI/EXEC to ensure
      # that all related operations succeed or fail together:
      # 1. Delete the session hash
      # 2. Delete the events list
      # 3. Remove the session ID from the global set
      #
      # @param session_id [String] The ID of the session to delete.
      # @return [Boolean] True if deletion commands were sent successfully, false otherwise.
      #                   Note: Doesn't guarantee keys existed before deletion.
      def delete_session(session_id:)
        session_key = redis_session_key(session_id)
        events_key = redis_events_key(session_id)

        begin
          # Execute deletion as a transaction to ensure atomicity
          results = @redis_client.multi do |multi|
            multi.del(session_key)
            multi.del(events_key)
            multi.srem(REDIS_SESSIONS_SET_KEY, session_id)
          end

          # Check results (number of keys deleted/removed)
          # results = [num_deleted_hash, num_deleted_list, num_removed_set]
          if results.is_a?(Array) && results.size == 3
            ADK.logger.info("Deleted session from Redis: #{session_id}. (Deleted #{results[0]} hash, #{results[1]} list keys, removed #{results[2]} from set)")
            true # Indicate command success
          else
            ADK.logger.warn("Unexpected result from Redis MULTI during session deletion for ID: #{session_id}. Results: #{results.inspect}")
            false # Indicate potential issue
          end
        rescue ::Redis::BaseError => e
          ADK.logger.error("Redis error deleting session #{session_id}: #{e.class} - #{e.message}")
          false
        end
      end

      # Lists sessions, optionally filtering by app_name or user_id.
      #
      # Uses Redis pipelining to efficiently fetch all session data in batched network calls
      # to improve performance compared to individual fetches.
      #
      # Warning: This can be inefficient for a large number of sessions.
      # @param app_name [String, nil] Optional filter by app name.
      # @param user_id [String, nil] Optional filter by user ID.
      # @return [Array<ADK::Session>] An array of session objects matching filters.
      def list_sessions(app_name: nil, user_id: nil)
        session_ids = @redis_client.smembers(REDIS_SESSIONS_SET_KEY)
        sessions = []

        # Use pipelining to fetch all session data more efficiently than N+1 calls
        return [] if session_ids.empty?

        begin
          pipeline_results = @redis_client.pipelined do |pipe|
            session_ids.each do |id|
              pipe.hgetall(redis_session_key(id))
              pipe.lrange(redis_events_key(id), 0, -1)
            end
          end

          # Process pipeline results (pairs of [hash_data, events_list])
          session_ids.each_with_index do |session_id, index|
            hash_data = pipeline_results[index * 2]
            events_list = pipeline_results[index * 2 + 1]

            next if hash_data.nil? || hash_data.empty? # Skip if hash is missing

            # --- Filtering ---
            next if app_name && hash_data['app_name'] != app_name
            next if user_id && hash_data['user_id'] != user_id

            # --- End Filtering ---

            # Deserialize state
            state = {}
            if hash_data['state']
              begin
                encrypted_state = JSON.parse(hash_data['state'], symbolize_names: true)
                state = process_state_from_storage(encrypted_state)
              rescue JSON::ParserError
                state = { _parse_error: 'Failed to load state' }
              end
            end

            # Deserialize events
            events = []
            events_list&.each do |event_json|
              event_h = JSON.parse(event_json, symbolize_names: true)
              ev = ADK::Event.from_h(event_h)
              events << ev if ev
            rescue JSON::ParserError
              # Skip events that can't be parsed
            end

            # Reconstruct Session object
            session_data_for_init = {
              id: session_id, app_name: hash_data['app_name'], user_id: hash_data['user_id'],
              initial_state: state, events: events, session_service: self
            }
            session = ADK::Session.new(**session_data_for_init)
            if hash_data['created_at']
              session.instance_variable_set(:@created_at,
                                            Time.iso8601(hash_data['created_at']))
            end
            if hash_data['updated_at']
              session.instance_variable_set(:@updated_at,
                                            Time.iso8601(hash_data['updated_at']))
            end
            sessions << session
          rescue ArgumentError, TypeError => e
            ADK.logger.error("Error reconstructing session object during list for ID #{session_id}: #{e.class} - #{e.message}")
            next # Skip this session if reconstruction fails
          end

          ADK.logger.debug("Listed #{sessions.count} sessions from Redis (after filtering).")
          sessions
        rescue ::Redis::BaseError => e
          ADK.logger.error("Redis error listing sessions: #{e.class} - #{e.message}")
          [] # Return empty on error
        end
      end

      # Retrieves a value from the state associated with the session.
      # @param session_id [String] The ID of the session.
      # @param key [Symbol] The key for the state entry.
      # @return [Object, nil] The value if found, or nil.
      def get_state(session_id:, key:)
        key_str = key.to_s
        if key_str.include?(':')
          prefix, real_key = key_str.split(':', 2)
          return load_scoped_state(prefix, real_key) if ADK::Session::VALID_PREFIXES.include?(prefix)
        end

        state_json = @redis_client.hget(redis_session_key(session_id), 'state')
        return nil unless state_json

        begin
          encrypted = JSON.parse(state_json, symbolize_names: true)
          process_state_from_storage(encrypted)[key.to_sym]
        rescue JSON::ParserError => e
          ADK.logger.error("Failed to parse state JSON for session #{session_id}: #{e.message}")
          nil
        end
      end

      # Sets a key-value pair in the state associated with the session.
      # @param session_id [String] The ID of the session.
      # @param key [Symbol] The key for the state entry.
      # @param value [Object] The value to store.
      # @return [void]
      def set_state(session_id:, key:, value:)
        event = ADK::Event.new(role: :system, content: "Setting state key '#{key}'", state_delta: { key => value })
        append_event(session_id: session_id, event: event)
        nil
      end

      # Indicates this session service implementation persists data.
      # @return [Boolean] Always returns true as Redis provides persistence.
      def persistent?
        true
      end

      # Saves a value in Redis with a scoped key for arbitrary state storage.
      # Encrypts sensitive data based on the scope and key.
      #
      # @param scope [String] The scope for the state (namespace).
      # @param key [String] The key within the scope.
      # @param value [Object] The value to store (must be JSON serializable).
      # @raise [ADK::Error] If serialization or Redis operations fail.
      def save_scoped_state(scope, key, value)
        state_key = redis_scoped_state_key(scope, key)

        begin
          # Encrypt sensitive data based on scope/key
          processed_value = if should_encrypt_scoped_state?(scope, key)
                              encrypt_value(value)
                            else
                              value
                            end

          value_json = JSON.generate(processed_value)
          @redis_client.set(state_key, value_json)
          @redis_client.expire(state_key, @session_ttl) if @session_ttl&.positive?
        rescue JSON::GeneratorError => e
          ADK.logger.error("Failed to serialize scoped state value: #{e.message}")
          raise ADK::Error, 'Failed to serialize scoped state value.'
        rescue ::Redis::BaseError => e
          ADK.logger.error("Redis error saving scoped state: #{e.class} - #{e.message}")
          raise ADK::Error, 'Redis error saving scoped state.'
        end
      end

      # Loads a value from Redis using a scoped key.
      # Automatically decrypts encrypted values.
      #
      # @param scope [String] The scope for the state (namespace).
      # @param key [String] The key within the scope.
      # @return [Object, nil] The deserialized value or nil if not found.
      def load_scoped_state(scope, key)
        state_key = redis_scoped_state_key(scope, key)

        begin
          value_json = @redis_client.get(state_key)
          return nil unless value_json

          value = JSON.parse(value_json, symbolize_names: true)

          # Try to decrypt if the value looks encrypted
          if @encryption_enabled && value.is_a?(String) &&
             ADK::Auth::Encryption.encrypted?(value)
            begin
              decrypted_value = ADK::Auth::Encryption.decrypt(value)
              return JSON.parse(decrypted_value, symbolize_names: true)
            rescue StandardError => e
              ADK.logger.warn("Failed to decrypt scoped state value (#{scope}:#{key}): #{e.message}")
              # Return value as-is if decryption fails
            end
          end

          value
        rescue JSON::ParserError => e
          ADK.logger.error("Failed to parse scoped state value: #{e.message}")
          nil
        rescue ::Redis::BaseError => e
          ADK.logger.error("Redis error loading scoped state: #{e.class} - #{e.message}")
          nil
        end
      end

      # Clears a scoped state value or all values in a scope.
      #
      # @param scope [String] The scope for the state (namespace).
      # @param key [String] The key within the scope, or '*' to clear all keys in the scope.
      # @return [Boolean] True if deletion was successful, false otherwise.
      def clear_scoped_state(scope, key)
        if key == '*'
          # Clear all keys in the scope
          pattern = redis_scoped_state_key(scope, '*')
          begin
            keys = @redis_client.keys(pattern)
            return true if keys.empty?

            # Delete keys in batches to avoid long-running DEL command
            keys.each_slice(100) do |batch|
              @redis_client.del(*batch)
            end
            true
          rescue ::Redis::BaseError => e
            ADK.logger.error("Redis error clearing scoped state with pattern #{pattern}: #{e.class} - #{e.message}")
            false
          end
        else
          # Clear a specific key
          state_key = redis_scoped_state_key(scope, key)
          begin
            @redis_client.del(state_key)
            true
          rescue ::Redis::BaseError => e
            ADK.logger.error("Redis error clearing scoped state for key #{state_key}: #{e.class} - #{e.message}")
            false
          end
        end
      end

      # Helper methods for auth token management

      # Stores an auth token in the session state
      # @param session [ADK::Session] The session to store the token in
      # @param cache_key [String, Symbol] A unique key for the token
      # @param token [ADK::Auth::ExchangedCredential] The token to store
      # @return [Boolean] True if the token was stored successfully
      def store_auth_token(session, cache_key, token)
        # Ensure auth_token_cache exists in state
        session.state[AUTH_TOKEN_CACHE_KEY] ||= {}

        # Serialize and encrypt the token
        serialized = JSON.generate(token.to_h)
        encrypted = encrypt_value(serialized)

        # Store in session state
        session.state[AUTH_TOKEN_CACHE_KEY][cache_key.to_sym] = encrypted

        # Append an event to update the session state in Redis
        event = ADK::Event.new(
          role: 'system',
          content: 'Auth token updated',
          state_delta: { AUTH_TOKEN_CACHE_KEY => session.state[AUTH_TOKEN_CACHE_KEY] }
        )
        append_event(session_id: session.id, event: event)
      end

      # Retrieves an auth token from the session state
      # @param session [ADK::Session] The session to retrieve the token from
      # @param cache_key [String, Symbol] The unique key for the token
      # @return [ADK::Auth::ExchangedCredential, nil] The token if found and valid, nil otherwise
      def retrieve_auth_token(session, cache_key)
        # Check if auth_token_cache exists
        return nil unless session.state[AUTH_TOKEN_CACHE_KEY]

        # Get the encrypted token
        encrypted = session.state[AUTH_TOKEN_CACHE_KEY][cache_key.to_sym]
        return nil unless encrypted

        # Decrypt and deserialize
        begin
          decrypted = decrypt_value(encrypted)
          token_hash = JSON.parse(decrypted, symbolize_names: true)

          # Convert to ExchangedCredential
          require_relative '../auth/exchanged_credential'
          ADK::Auth::ExchangedCredential.from_h(token_hash)
        rescue StandardError => e
          ADK.logger.error("Failed to retrieve auth token: #{e.message}")
          nil
        end
      end

      # Generate a new encryption key and return it
      # @return [String] A new encryption key in Base64 format
      def generate_encryption_key
        ADK::Auth::Encryption.generate_key
      end

      private

      # Establishes a connection to Redis using default configuration.
      #
      # @return [Redis] An initialized Redis client.
      # @raise [ADK::Error] If connection to Redis fails.
      def connect_redis
        redis = ::Redis.new # Assumes localhost:6379
        redis.ping # Verify connection
        redis
      rescue ::Redis::BaseError => e
        ADK.logger.fatal("Could not connect to Redis for session service: #{e.message}")
        raise ADK::Error, "Could not connect to Redis for session service: #{e.message}"
      end

      # Generates the Redis hash key for a session.
      #
      # @param session_id [String] The session ID.
      # @return [String] The Redis key for the session hash.
      def redis_session_key(session_id)
        "#{REDIS_SESSION_HASH_PREFIX}#{session_id}"
      end

      # Generates the Redis list key for a session's events.
      #
      # @param session_id [String] The session ID.
      # @return [String] The Redis key for the session events list.
      def redis_events_key(session_id)
        "#{REDIS_SESSION_EVENTS_LIST_PREFIX}#{session_id}"
      end

      # Generates the Redis key for scoped state.
      #
      # @param scope [String] The scope (namespace).
      # @param key [String] The key within the scope.
      # @return [String] The Redis key for the scoped state.
      def redis_scoped_state_key(scope, key)
        "#{REDIS_SCOPED_STATE_PREFIX}#{scope}:#{key}"
      end

      # Process state before storage, encrypting sensitive fields
      # @param state [Hash] The state to process
      # @return [Hash] The processed state with encrypted fields
      def process_state_for_storage(state)
        return state unless @encryption_enabled

        processed = {}

        state.each do |key, value|
          processed[key] = if should_encrypt_field?(key) && value
                             encrypt_value(value)
                           else
                             value
                           end
        end

        processed
      end

      # Process state after retrieval, decrypting encrypted fields
      # @param state [Hash] The state to process
      # @return [Hash] The processed state with decrypted fields
      def process_state_from_storage(state)
        return state unless @encryption_enabled

        processed = {}

        state.each do |key, value|
          if should_encrypt_field?(key) && value && value.is_a?(String) &&
             ADK::Auth::Encryption.encrypted?(value)
            begin
              processed[key] = decrypt_value(value)
            rescue StandardError => e
              ADK.logger.warn("Failed to decrypt state field #{key}: #{e.message}")
              processed[key] = value
            end
          else
            processed[key] = value
          end
        end

        processed
      end

      # Check if a field should be encrypted
      # @param field [Symbol] The field to check
      # @return [Boolean] True if the field should be encrypted
      def should_encrypt_field?(field)
        SENSITIVE_FIELDS.include?(field.to_sym)
      end

      # Check if scoped state should be encrypted
      # @param scope [String] The scope
      # @param key [String] The key
      # @return [Boolean] True if the state should be encrypted
      def should_encrypt_scoped_state?(scope, key)
        scope == 'auth' ||
          scope == 'credentials' ||
          key.to_s.include?('token') ||
          key.to_s.include?('secret') ||
          key.to_s.include?('password') ||
          key.to_s.include?('key')
      end

      # Encrypt a value for storage
      # @param value [Object] The value to encrypt
      # @return [String] The encrypted value
      def encrypt_value(value)
        return value unless @encryption_enabled

        # Convert non-string values to JSON before encryption
        value = JSON.generate(value) unless value.is_a?(String)

        ADK::Auth::Encryption.encrypt(value)
      rescue StandardError => e
        ADK.logger.warn("Encryption failed, storing unencrypted: #{e.message}")
        value
      end

      # Decrypt a value from storage
      # @param encrypted [String] The encrypted value
      # @return [Object] The decrypted value
      def decrypt_value(encrypted)
        return encrypted unless @encryption_enabled && encrypted.is_a?(String) &&
                                ADK::Auth::Encryption.encrypted?(encrypted)

        decrypted = ADK::Auth::Encryption.decrypt(encrypted)

        # Try to parse as JSON in case it was a serialized object
        begin
          JSON.parse(decrypted, symbolize_names: true)
        rescue JSON::ParserError
          # Return as string if not valid JSON
          decrypted
        end
      end
    end
  end
end
