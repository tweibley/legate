# File: lib/legate/session_service/in_memory.rb
# frozen_string_literal: true

require 'concurrent'
require_relative 'base'
require_relative 'event_broadcast'
require_relative '../session'
require_relative '../event'

module Legate
  module SessionService
    # Stores sessions entirely in memory. Data is lost on application restart.
    # Useful for local development, testing, and simple use cases.
    class InMemory < Base
      include EventBroadcast

      attr_reader :sessions, :scoped_states

      def initialize
        @sessions = Concurrent::Map.new
        @scoped_states = Concurrent::Map.new
        Legate.logger.info('InMemorySessionService initialized.')
      end

      def persistent?
        false
      end

      # Creates a new session in memory.
      # @param app_name [String] Identifier for the agent application.
      # @param user_id [String] Identifier for the user initiating the session.
      # @param session_id [String, nil] Optional explicit session id (defaults to a generated UUID).
      # @param initial_state [Hash] Optional initial data for the session state.
      # @return [Legate::Session] The newly created session object.
      def create_session(app_name:, user_id:, session_id: nil, initial_state: {})
        # Fix: Ensure keys are symbols before passing to Session constructor
        symbolized_state = initial_state.transform_keys { |k|
          begin
            k.to_sym
          rescue StandardError
            k
          end
        }
        session = Legate::Session.new(
          app_name: app_name,
          user_id: user_id,
          id: session_id,
          initial_state: symbolized_state,
          session_service: self
        )
        @sessions[session.id] = session
        Legate.logger.info("Created session: #{session.id} for app:#{app_name}, user:#{user_id}")
        session
      end

      # Retrieves a session from memory by its ID.
      # @param session_id [String] The unique ID of the session to retrieve.
      # @return [Legate::Session, nil] The session object if found, otherwise nil.
      def get_session(session_id:)
        session = @sessions[session_id]
        if session
          Legate.logger.debug("Retrieved session: #{session_id}")
        else
          Legate.logger.warn("Session not found: #{session_id}")
        end
        session
      end

      # --- DEPRECATED ---
      # Saves the session state (in memory this just means it's already updated).
      # In a persistent store, this would write changes. Here, we just update the timestamp.
      # NOTE: Events and state updates should be done via #append_event for atomicity.
      # This method mainly exists for interface compatibility if needed but should be avoided.
      # @param session [Legate::Session] The session object to "save".
      # @return [Boolean] True if the session exists in memory.
      def save_session(session:)
        if @sessions.key?(session.id)
          session.updated_at = Time.now.utc # Ensure timestamp reflects save attempt
          Legate.logger.warn('InMemorySessionService#save_session called (likely unnecessary). Use append_event.')
          true
        else
          Legate.logger.error("Attempted to save non-existent session: #{session.id}")
          false
        end
      end

      # --- REVISED METHOD ---
      # Appends an event to a session and merges state updates from the event's state_delta.
      # This should be the primary way to modify a session during a turn.
      # @param session_id [String] The ID of the session to update.
      # @param event [Legate::Event] The event to append. Must be an instance of Legate::Event.
      # @return [Boolean] True if successful, false if session not found or event is invalid.
      def append_event(session_id:, event:)
        session = get_session(session_id: session_id)
        return false unless session

        session.add_event(event)
        broadcast_event(session_id, event) # notify any streaming subscribers (R3)
        true
      end

      # Deletes a session from memory.
      # @param session_id [String] The ID of the session to delete.
      # @return [Boolean] True if a session was deleted, false otherwise.
      def delete_session(session_id:)
        deleted_session = @sessions.delete(session_id)
        if deleted_session
          Legate.logger.info("Deleted session: #{session_id}")
          true
        else
          Legate.logger.warn("Attempted to delete non-existent session: #{session_id}")
          false
        end
      end

      # Lists sessions (in this implementation, just returns all session objects).
      # Filtering could be added later if needed.
      # @param app_name [String, nil] Optional filter by app name.
      # @param user_id [String, nil] Optional filter by user ID.
      # @return [Array<Legate::Session>] An array of session objects matching filters.
      def list_sessions(app_name: nil, user_id: nil)
        filtered = @sessions.values # Get all session objects
        filtered.select! { |s| s.app_name == app_name } if app_name
        filtered.select! { |s| s.user_id == user_id } if user_id
        Legate.logger.debug("Listing #{filtered.count} sessions.")
        filtered
      end

      def save_scoped_state(scope, key, value)
        state_key = "#{scope}:#{key}"
        @scoped_states[state_key] = value
      end

      def load_scoped_state(scope, key)
        state_key = "#{scope}:#{key}"
        @scoped_states[state_key]
      end

      def clear_scoped_state(scope, key)
        if key == '*'
          # Clear all states for the given scope
          @scoped_states.keys.each do |state_key|
            @scoped_states.delete(state_key) if state_key.start_with?("#{scope}:")
          end
        else
          state_key = "#{scope}:#{key}"
          @scoped_states.delete(state_key)
        end
      end

      # Sets a key-value pair in the state associated with the session.
      # Delegates to the Legate::Session instance's set_state method.
      # @param session_id [String] The ID of the session.
      # @param key [Symbol] The key for the state entry.
      # @param value [Object] The value to store.
      # @return [void]
      def set_state(session_id:, key:, value:)
        session = get_session(session_id: session_id)
        if session
          begin
            session.set_state(key, value) # Legate::Session#set_state handles its own logging
          rescue Legate::SerializationError => e # Catch potential serialization errors from session.set_state
            Legate.logger.error("InMemorySessionService: Error setting state for session '#{session_id}', key '#{key}': #{e.message}")
            # Depending on desired behavior, could re-raise or just log
          end
        else
          Legate.logger.warn("InMemorySessionService: Session not found '#{session_id}' when trying to set state for key '#{key}'.")
        end
        nil # Return void consistent with base
      end

      # Retrieves a value from the state associated with the session.
      # Delegates to the Legate::Session instance's get_state method.
      # @param session_id [String] The ID of the session.
      # @param key [Symbol] The key for the state entry.
      # @return [Object, nil] The value if found, or nil.
      def get_state(session_id:, key:)
        session = get_session(session_id: session_id)
        if session
          session.get_state(key) # Legate::Session#get_state handles its own logic
        else
          Legate.logger.warn("InMemorySessionService: Session not found '#{session_id}' when trying to get state for key '#{key}'.")
          nil
        end
      end
    end
  end
end
