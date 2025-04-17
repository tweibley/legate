# File: lib/adk/session_service/redis.rb
# frozen_string_literal: true

require 'redis'
require 'json'
require 'time' # For iso8601 parsing
require_relative '../session'
require_relative '../event'
require_relative 'base'

module ADK
  module SessionService
    # Stores sessions in Redis for persistence.
    # Uses a Redis Hash for metadata/state and a Redis List for events.
    class Redis < Base
      # Key Definitions
      REDIS_SESSION_HASH_PREFIX = "adk:session:"
      REDIS_SESSION_EVENTS_LIST_PREFIX = "adk:session:events:"
      REDIS_SESSIONS_SET_KEY = "adk:sessions:all_ids"
      REDIS_SCOPED_STATE_PREFIX = "adk:state:"

      # Default TTL for session keys (in seconds). Set to nil or 0 for no expiry.
      # Example: 7 days = 7 * 24 * 60 * 60 = 604800
      DEFAULT_SESSION_TTL = 604_800

      attr_reader :redis_client, :session_ttl

      # Initializes the service with a Redis client.
      # @param redis_client [Redis] An active Redis client instance.
      # @param session_ttl [Integer, nil] TTL for session keys in seconds (nil for no expiry).
      def initialize(redis_client: nil, session_ttl: DEFAULT_SESSION_TTL)
        @redis_client = redis_client || connect_redis
        @session_ttl = session_ttl
        ADK.logger.info("RedisSessionService initialized. Session TTL: #{session_ttl || 'None'}")
      end

      # Creates a new session and stores it in Redis.
      # @param app_name [String] Identifier for the agent application.
      # @param user_id [String] Identifier for the user initiating the session.
      # @param initial_state [Hash] Optional initial data for the session state.
      # @return [ADK::Session] The newly created session object.
      def create_session(app_name:, user_id:, initial_state: {})
        session = ADK::Session.new(
          app_name: app_name,
          user_id: user_id,
          initial_state: initial_state,
          session_service: self
        )
        session_key = redis_session_key(session.id)
        events_key = redis_events_key(session.id)

        begin
          state_json = JSON.generate(session.state_to_h)
          session_data = {
            app_name: session.app_name,
            user_id: session.user_id,
            created_at: session.created_at.iso8601(3),
            updated_at: session.updated_at.iso8601(3),
            state: state_json
          }

          results = @redis_client.multi do |multi|
            multi.hset(session_key, session_data)
            multi.sadd(REDIS_SESSIONS_SET_KEY, session.id)
            # Optionally set TTL if configured
            if @session_ttl&.positive?
              multi.expire(session_key, @session_ttl)
              # Note: Events list doesn't have TTL set automatically here, might orphan data.
              # Consider adding TTL to events list too, or manage cleanup separately.
              multi.expire(events_key, @session_ttl) if @redis_client.exists?(events_key) # Only if list exists
            end
          end

          # Basic check on multi results (can be more specific if needed)
          unless results.all?
            ADK.logger.error("Redis MULTI command failed during session creation for ID: #{session.id}. Results: #{results.inspect}")
            # Consider cleanup or raising an error
            raise ADK::Error, "Failed to create session in Redis."
          end

          ADK.logger.info("Created session in Redis: #{session.id} for app:#{app_name}, user:#{user_id}")
          session
        rescue JSON::GeneratorError => e
          ADK.logger.error("Failed to serialize session state for #{session.id}: #{e.message}")
          raise ADK::Error, "Failed to serialize session state."
        rescue ::Redis::BaseError => e
          ADK.logger.error("Redis error creating session #{session.id}: #{e.class} - #{e.message}")
          raise ADK::Error, "Redis error during session creation."
        end
      end

      # Retrieves a session from Redis by its ID.
      # @param session_id [String] The unique ID of the session to retrieve.
      # @return [ADK::Session, nil] The session object if found, otherwise nil.
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

          # Check if session hash exists
          if session_hash_data.nil? || session_hash_data.empty?
            ADK.logger.warn("Session not found in Redis: #{session_id}")
            return nil
          end

          # Deserialize session state
          state = {}
          if session_hash_data['state']
            begin
              state = JSON.parse(session_hash_data['state'], symbolize_names: true)
            rescue JSON::ParserError => e
              ADK.logger.error("Failed to parse state JSON for session #{session_id}: #{e.message}. Data: #{session_hash_data['state']}")
              state = { _parse_error: "Failed to load state: #{e.message}" } # Include error in state
            end
          end

          # Deserialize events
          events = []
          if event_json_list
            event_json_list.each_with_index do |event_json, index|
              begin
                event_hash = JSON.parse(event_json, symbolize_names: true)
                event = ADK::Event.from_h(event_hash)
                events << event if event # from_h returns nil on error
              rescue JSON::ParserError => e
                ADK.logger.error("Failed to parse event JSON at index #{index} for session #{session_id}: #{e.message}. Data: #{event_json}")
                # Optionally add a placeholder event? Or just skip. Skipping for now.
              end
            end
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
          session.instance_variable_set(:@created_at,
                                        Time.iso8601(session_hash_data['created_at'])) if session_hash_data['created_at']
          session.instance_variable_set(:@updated_at,
                                        Time.iso8601(session_hash_data['updated_at'])) if session_hash_data['updated_at']

          ADK.logger.debug("Retrieved session from Redis: #{session_id}")
          session
        rescue ::Redis::BaseError => e
          ADK.logger.error("Redis error getting session #{session_id}: #{e.class} - #{e.message}")
          raise ADK::Error, "Redis error during session retrieval."
        rescue ArgumentError, TypeError => e # Catch potential errors in Time.iso8601 or Session init
          ADK.logger.error("Error reconstructing session object for #{session_id}: #{e.class} - #{e.message}")
          nil # Return nil if reconstruction fails
        end
      end

      # Appends an event to a session's event list and updates the state and timestamp in Redis.
      # Uses WATCH/MULTI/EXEC for optimistic locking on the session state.
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
        max_retries = 3
        retries = 0

        begin
          loop do
            # Watch the session key for changes
            @redis_client.watch(session_key) do
              # If event has state_delta, fetch current state
              if event.state_delta && !event.state_delta.empty?
                current_state_json = @redis_client.hget(session_key, 'state')
                if current_state_json
                  begin
                    current_state = JSON.parse(current_state_json, symbolize_names: true)
                    session.update_state(current_state.merge(event.state_delta))
                  rescue JSON::ParserError => e
                    ADK.logger.error("Failed to parse current state JSON for session #{session_id}: #{e.message}")
                    return false
                  end
                end
              end

              # Update Redis in a transaction
              results = @redis_client.multi do |multi|
                # Add event to the events list
                multi.rpush(events_key, JSON.generate(added_event.to_h))

                # Update session hash with new state and timestamp
                multi.hset(session_key, 'updated_at', session.updated_at.iso8601(3))
                multi.hset(session_key, 'state', JSON.generate(session.state_to_h))

                # Refresh TTL if configured
                if @session_ttl&.positive?
                  multi.expire(session_key, @session_ttl)
                  multi.expire(events_key, @session_ttl)
                end
              end

              # Check if transaction was successful
              if results.nil?
                # Watch failed, retry if we haven't exceeded max retries
                retries += 1
                if retries >= max_retries
                  ADK.logger.warn("Max retries (#{max_retries}) exceeded for session #{session_id} event append")
                  return false
                end
                next
              end

              # Check if all commands succeeded
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
          @redis_client.unwatch rescue nil # Best effort to unwatch
          false
        end
      end

      # Deletes a session and its associated events list from Redis.
      # @param session_id [String] The ID of the session to delete.
      # @return [Boolean] True if deletion commands were sent successfully, false otherwise.
      #                   Note: Doesn't guarantee keys existed before deletion.
      def delete_session(session_id:)
        session_key = redis_session_key(session_id)
        events_key = redis_events_key(session_id)

        begin
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
              begin; state = JSON.parse(hash_data['state'], symbolize_names: true); rescue JSON::ParserError;
                                                                                      state = { _parse_error: "Failed to load state" };
              end
            end

            # Deserialize events
            events = []
            if events_list
              events_list.each do |event_json|
                begin;
 event_h = JSON.parse(event_json, symbolize_names: true);
 ev = ADK::Event.from_h(event_h); events << ev if ev; rescue JSON::ParserError; end
              end
            end

            # Reconstruct Session object
            session_data_for_init = {
              id: session_id, app_name: hash_data['app_name'], user_id: hash_data['user_id'],
              initial_state: state, events: events, session_service: self
            }
            session = ADK::Session.new(**session_data_for_init)
            session.instance_variable_set(:@created_at,
                                          Time.iso8601(hash_data['created_at'])) if hash_data['created_at']
            session.instance_variable_set(:@updated_at,
                                          Time.iso8601(hash_data['updated_at'])) if hash_data['updated_at']
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

      def persistent?
        true
      end

      def save_scoped_state(scope, key, value)
        state_key = redis_scoped_state_key(scope, key)
        begin
          value_json = JSON.generate(value)
          @redis_client.set(state_key, value_json)
          if @session_ttl&.positive?
            @redis_client.expire(state_key, @session_ttl)
          end
        rescue JSON::GeneratorError => e
          ADK.logger.error("Failed to serialize scoped state value: #{e.message}")
          raise ADK::Error, "Failed to serialize scoped state value."
        rescue ::Redis::BaseError => e
          ADK.logger.error("Redis error saving scoped state: #{e.class} - #{e.message}")
          raise ADK::Error, "Redis error saving scoped state."
        end
      end

      def load_scoped_state(scope, key)
        state_key = redis_scoped_state_key(scope, key)
        begin
          value_json = @redis_client.get(state_key)
          return nil unless value_json

          JSON.parse(value_json, symbolize_names: true)
        rescue JSON::ParserError => e
          ADK.logger.error("Failed to parse scoped state value: #{e.message}")
          nil
        rescue ::Redis::BaseError => e
          ADK.logger.error("Redis error loading scoped state: #{e.class} - #{e.message}")
          nil
        end
      end

      def clear_scoped_state(scope, key)
        if key == '*'
          pattern = redis_scoped_state_key(scope, '*')
          keys = @redis_client.keys(pattern)
          @redis_client.del(*keys) unless keys.empty?
        else
          state_key = redis_scoped_state_key(scope, key)
          @redis_client.del(state_key)
        end
      rescue ::Redis::BaseError => e
        ADK.logger.error("Redis error clearing scoped state: #{e.class} - #{e.message}")
        raise ADK::Error, "Redis error clearing scoped state."
      end

      private

      # Connects to Redis using default settings.
      # TODO: Allow configuration via ENV variables or options.
      # @return [Redis] Connected Redis client instance.
      def connect_redis
        redis = ::Redis.new # Assumes localhost:6379
        redis.ping # Verify connection
        redis
      rescue ::Redis::CannotConnectError => e
        ADK.logger.fatal("FATAL: Could not connect to Redis. Session persistence disabled. #{e.message}")
        raise ADK::Error, "Could not connect to Redis for session service: #{e.message}"
      end

      # Generates the Redis key for the session hash.
      # @param session_id [String]
      # @return [String]
      def redis_session_key(session_id)
        "#{REDIS_SESSION_HASH_PREFIX}#{session_id}"
      end

      # Generates the Redis key for the session events list.
      # @param session_id [String]
      # @return [String]
      def redis_events_key(session_id)
        "#{REDIS_SESSION_EVENTS_LIST_PREFIX}#{session_id}"
      end

      def redis_scoped_state_key(scope, key)
        "#{REDIS_SCOPED_STATE_PREFIX}#{scope}:#{key}"
      end
    end # End Redis class
  end # End SessionService module
end # End ADK module
