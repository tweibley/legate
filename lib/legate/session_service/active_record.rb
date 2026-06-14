# File: lib/legate/session_service/active_record.rb
# frozen_string_literal: true

# Opt-in: this file is NOT loaded by `require 'legate'`. Require it explicitly
# (and have ActiveRecord available + a connection established) to use a durable,
# ActiveRecord-backed session store. In Rails, `require 'legate/rails'` wires
# this up and `rails g legate:install` creates the migration.
require 'active_record'
require 'json'
require_relative 'base'
require_relative 'event_broadcast'
require_relative '../session'
require_relative '../event'

module Legate
  module SessionService
    # Durable session store backed by ActiveRecord (subsumes R2 persistence).
    #
    # Semantics mirror InMemory — repeated get_session within a process returns
    # the same Session object so a run's mutations accumulate — but every
    # mutation is written through to the database, so a restart or another
    # process re-hydrates the committed history and state from rows.
    #
    # The host application owns the AR connection (Rails does this for you;
    # standalone users call ActiveRecord::Base.establish_connection). Tables are
    # created by the generated migration, or ad hoc via {.create_tables!}.
    class ActiveRecord < Base
      include EventBroadcast

      # Abstract base so every Legate table shares the host's connection.
      class Record < ::ActiveRecord::Base
        self.abstract_class = true
      end

      # A persisted conversation (id is the Session UUID).
      class SessionRecord < Record
        self.table_name = 'legate_sessions'
        serialize :state, coder: JSON
        has_many :event_records, -> { order(:position) },
                 class_name: 'Legate::SessionService::ActiveRecord::EventRecord',
                 foreign_key: :legate_session_id, inverse_of: :session_record
      end

      # One appended event, ordered within its session by `position`.
      class EventRecord < Record
        self.table_name = 'legate_events'
        serialize :content, coder: JSON
        serialize :state_delta, coder: JSON
        belongs_to :session_record,
                   class_name: 'Legate::SessionService::ActiveRecord::SessionRecord',
                   foreign_key: :legate_session_id, inverse_of: :event_records
      end

      # Scoped (user:/app:/temp:) state, keyed by the namespaced scope + key.
      class ScopedStateRecord < Record
        self.table_name = 'legate_scoped_states'
        serialize :value, coder: JSON
      end

      # Creates the three Legate tables if absent. Convenience for tests and
      # standalone (non-migration) setups; Rails apps use the generated migration.
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      def self.create_tables!(connection: Record.connection)
        unless connection.table_exists?(:legate_sessions)
          connection.create_table :legate_sessions, id: :string do |t|
            t.string :app_name
            t.string :user_id
            t.text :state
            t.timestamps
          end
        end

        unless connection.table_exists?(:legate_events)
          connection.create_table :legate_events do |t|
            t.string :legate_session_id, null: false, index: true
            t.integer :position, null: false, default: 0
            t.string :role
            t.text :content
            t.string :tool_name
            t.text :state_delta
            t.string :event_timestamp
            t.string :event_id
            t.timestamps
          end
        end

        return if connection.table_exists?(:legate_scoped_states)

        connection.create_table :legate_scoped_states do |t|
          t.string :scope, null: false
          t.string :state_key, null: false
          t.text :value
          t.timestamps
        end
        connection.add_index :legate_scoped_states, %i[scope state_key], unique: true,
                                                                         name: 'index_legate_scoped_states_on_scope_and_key'
      end

      # Cap on cached Session objects. The cache gives a run a stable Session
      # identity and avoids re-hydrating on every get_session; because every
      # mutation is written through, an evicted session re-hydrates correctly
      # from the database. LRU eviction only ever reclaims idle sessions — an
      # active run keeps touching (and so keeps) its own session.
      DEFAULT_MAX_CACHED_SESSIONS = 1_000

      # @param max_cached_sessions [Integer] LRU bound for the in-process cache
      def initialize(max_cached_sessions: DEFAULT_MAX_CACHED_SESSIONS)
        super()
        @cache = {} # insertion order = LRU order; guarded by @cache_mutex
        @cache_mutex = Mutex.new
        @max_cached_sessions = max_cached_sessions
        Legate.logger.info('ActiveRecord session service initialized.')
      end

      def persistent?
        true
      end

      def create_session(app_name:, user_id:, session_id: nil, initial_state: {})
        session = Legate::Session.new(
          app_name: app_name, user_id: user_id, id: session_id,
          initial_state: symbolize(initial_state), session_service: self
        )
        SessionRecord.create!(
          id: session.id, app_name: app_name, user_id: user_id, state: session.state_to_h
        )
        cache_put(session.id, session)
        Legate.logger.info("Created persistent session: #{session.id} for app:#{app_name}, user:#{user_id}")
        session
      end

      def get_session(session_id:)
        cached = cache_get(session_id)
        return cached if cached

        record = SessionRecord.find_by(id: session_id)
        unless record
          Legate.logger.warn("Session not found: #{session_id}")
          return nil
        end

        session = hydrate(record)
        cache_put(session_id, session)
        session
      end

      def append_event(session_id:, event:)
        session = get_session(session_id: session_id)
        return false unless session

        session.add_event(event) # merges state_delta into the cached Session
        # The event row and the merged session state must land together, or
        # neither — otherwise a crash between them leaves history and state
        # inconsistent.
        SessionRecord.transaction do
          insert_event(session_id, event)
          write_session_state(session_id, session)
        end
        broadcast_event(session_id, event) # notify any streaming subscribers (R3)
        true
      rescue ::ActiveRecord::ActiveRecordError => e
        Legate.logger.error("ActiveRecord session service: append_event failed for '#{session_id}': #{e.message}")
        # The write rolled back but the cached Session already holds the event;
        # drop it so the next get_session re-hydrates the committed truth.
        cache_evict(session_id)
        false
      end

      def delete_session(session_id:)
        cache_evict(session_id)
        EventRecord.where(legate_session_id: session_id).delete_all
        deleted = SessionRecord.where(id: session_id).delete_all
        if deleted.positive?
          Legate.logger.info("Deleted persistent session: #{session_id}")
          true
        else
          Legate.logger.warn("Attempted to delete non-existent session: #{session_id}")
          false
        end
      end

      def list_sessions(app_name: nil, user_id: nil)
        scope = SessionRecord.all
        scope = scope.where(app_name: app_name) if app_name
        scope = scope.where(user_id: user_id) if user_id
        scope.pluck(:id).filter_map { |id| get_session(session_id: id) }
      end

      def save_scoped_state(scope, key, value)
        record = ScopedStateRecord.find_or_initialize_by(scope: scope.to_s, state_key: key.to_s)
        record.value = value
        record.save!
      end

      def load_scoped_state(scope, key)
        ScopedStateRecord.find_by(scope: scope.to_s, state_key: key.to_s)&.value
      end

      def clear_scoped_state(scope, key)
        relation = ScopedStateRecord.where(scope: scope.to_s)
        relation = relation.where(state_key: key.to_s) unless key == '*'
        relation.delete_all
      end

      def set_state(session_id:, key:, value:)
        session = get_session(session_id: session_id)
        unless session
          Legate.logger.warn("ActiveRecord session service: Session not found '#{session_id}' when setting state for '#{key}'.")
          return nil
        end

        session.set_state(key, value)
        # Scoped keys are already persisted via save_scoped_state; write through
        # the plain-key state so it survives a restart.
        write_session_state(session_id, session)
        nil
      rescue Legate::SerializationError => e
        Legate.logger.error("ActiveRecord session service: Error setting state for '#{session_id}', key '#{key}': #{e.message}")
        nil
      end

      def get_state(session_id:, key:)
        session = get_session(session_id: session_id)
        return session.get_state(key) if session

        Legate.logger.warn("ActiveRecord session service: Session not found '#{session_id}' when getting state for '#{key}'.")
        nil
      end

      private

      # --- Bounded LRU session cache (guarded by @cache_mutex) ---

      # Return the cached session and mark it most-recently-used.
      def cache_get(session_id)
        @cache_mutex.synchronize do
          session = @cache.delete(session_id)
          @cache[session_id] = session if session # reinsert at the tail (MRU)
          session
        end
      end

      # Cache the session as most-recently-used, evicting the LRU entry if over cap.
      def cache_put(session_id, session)
        @cache_mutex.synchronize do
          @cache.delete(session_id)
          @cache[session_id] = session
          @cache.delete(@cache.keys.first) if @cache.size > @max_cached_sessions
        end
      end

      def cache_evict(session_id)
        @cache_mutex.synchronize { @cache.delete(session_id) }
      end

      def insert_event(session_id, event)
        next_position = (EventRecord.where(legate_session_id: session_id).maximum(:position) || 0) + 1
        EventRecord.create!(
          legate_session_id: session_id, position: next_position,
          role: event.role&.to_s, content: event.content, tool_name: event.tool_name&.to_s,
          state_delta: event.state_delta, event_timestamp: event.timestamp&.iso8601(3), event_id: event.event_id
        )
      end

      # Write-through the session's plain-key state (scoped state is persisted
      # separately via save_scoped_state). Shared by append_event and set_state.
      def write_session_state(session_id, session)
        SessionRecord.find_by(id: session_id)&.update!(state: session.state_to_h, updated_at: session.updated_at)
      end

      def hydrate(record)
        events = record.event_records.map { |er| hydrate_event(er) }.compact
        session = Legate::Session.new(
          id: record.id, app_name: record.app_name, user_id: record.user_id,
          initial_state: record.state || {}, events: events, session_service: self
        )
        session.instance_variable_set(:@created_at, record.created_at) if record.created_at
        session.updated_at = record.updated_at if record.updated_at
        session
      end

      def hydrate_event(record)
        Legate::Event.from_h(
          role: record.role, content: record.content, timestamp: record.event_timestamp,
          tool_name: record.tool_name, state_delta: record.state_delta, event_id: record.event_id
        )
      end

      def symbolize(hash)
        return {} unless hash.is_a?(Hash)

        hash.transform_keys do |k|
          k.to_sym
        rescue StandardError
          k
        end
      end
    end
  end
end
