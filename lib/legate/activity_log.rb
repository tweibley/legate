# frozen_string_literal: true

module Legate
  # Simple in-memory activity log for tracking system events.
  class ActivityLog
    MAX_EVENTS = 50

    class << self
      def instance
        @instance ||= new
      end

      # Delegate class methods to instance
      def log(event_type, details = {})
        instance.log(event_type, details)
      end

      # Records an event, swallowing any error — activity logging must never
      # break the request that triggered it.
      def safe_log(event_type, details = {})
        log(event_type, details)
      rescue StandardError => e
        Legate.logger&.debug { "ActivityLog: failed to record #{event_type}: #{e.message}" }
      end

      def recent(limit = 10)
        instance.recent(limit)
      end

      def clear
        instance.clear
      end
    end

    def initialize
      @events = []
      @mutex = Mutex.new
    end

    # Log a new event
    # @param event_type [Symbol] Type of event (:agent_started, :agent_stopped, etc.)
    # @param details [Hash] Event details (e.g., { name: 'agent_name' })
    def log(event_type, details = {})
      @mutex.synchronize do
        event = {
          type: event_type.to_sym,
          details: details,
          timestamp: Time.now.utc
        }
        @events.unshift(event)
        @events = @events.first(MAX_EVENTS)
      end
    end

    # Get recent events
    # @param limit [Integer] Number of events to return
    # @return [Array<Hash>] Recent events
    def recent(limit = 10)
      @mutex.synchronize do
        @events.first(limit)
      end
    end

    # Clear all events
    def clear
      @mutex.synchronize do
        @events = []
      end
    end
  end
end
