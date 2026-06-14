# File: lib/legate/session_service/event_broadcast.rb
# frozen_string_literal: true

require 'concurrent'

module Legate
  module SessionService
    # Session-scoped pub/sub for streaming agent events (R3).
    #
    # A session service includes this mixin and calls {#broadcast_event} right
    # after persisting an event in #append_event. Consumers (a Sinatra SSE
    # response, a CLI, a test) {#subscribe} to a session_id and receive each
    # event as it is appended, then {#unsubscribe} when done.
    #
    # Delivery is synchronous and in-order on the appending thread; a subscriber
    # that raises is isolated (logged, never breaks persistence or other
    # subscribers). Subscribers are keyed by session_id, so concurrent runs on
    # different sessions never cross.
    module EventBroadcast
      # Guards the one-time creation of the subscriber registry. Shared across
      # instances, but only contended on each instance's very first subscribe —
      # negligible, and it avoids depending on the including class's #initialize.
      INIT_LOCK = Mutex.new
      private_constant :INIT_LOCK

      # @param session_id [String]
      # @yieldparam event [Legate::Event] each event appended to this session
      # @return [Object] an opaque handle to pass to {#unsubscribe}
      def subscribe(session_id, &listener)
        raise ArgumentError, 'subscribe requires a block' unless listener

        key = session_id.to_s
        subscribers = event_subscribers.compute_if_absent(key) { Concurrent::Array.new }
        subscribers << listener
        [key, listener]
      end

      # Removes a subscription created by {#subscribe}. Safe to call twice / with nil.
      # @param handle [Object] the value returned by {#subscribe}
      def unsubscribe(handle)
        return unless handle.is_a?(Array)

        key, listener = handle
        subscribers = event_subscribers[key]
        return unless subscribers

        subscribers.delete(listener)
        event_subscribers.delete(key) if subscribers.empty?
      end

      # Notifies subscribers of `session_id` that `event` was appended.
      # @return [void]
      def broadcast_event(session_id, event)
        subscribers = event_subscribers[session_id.to_s]
        return if subscribers.nil? || subscribers.empty?

        subscribers.each do |listener|
          listener.call(event)
        rescue StandardError => e
          Legate.logger.error("EventBroadcast: subscriber raised #{e.class}: #{e.message}")
        end
      end

      private

      # Thread-safe lazy registry: the fast path is lock-free; the first caller
      # per instance takes INIT_LOCK so concurrent first-subscribers can't each
      # create (and orphan) a separate map.
      def event_subscribers
        @event_subscribers || INIT_LOCK.synchronize { @event_subscribers ||= Concurrent::Map.new }
      end
    end
  end
end
