**1. Publishing Events to Redis Pub/Sub**

*   **Where to Publish:** The most logical place to integrate the publish action is within the `ADK::SessionService::Redis` class, specifically in the `append_event` method. After an event is successfully persisted to the Redis list and the session hash is updated, it can then be published. This ensures that watchers only see events that are durably saved.
*   **Configuration:**
    *   Add a new configuration option, e.g., `ADK.config.enable_realtime_event_publishing = false` (default to `false` so it's opt-in).
    *   The `ADK::SessionService::Redis` would check this flag before attempting to publish.
*   **Channel Naming:** A good convention for Redis channels would be session-specific, e.g., `adk:events:session:<session_id>`.
*   **Data Format:** The `ADK::Event` object would be serialized to JSON (using `event.to_h.to_json`) before publishing.
*   **Redis Client for Publishing:** You might use the same Redis client instance already in `ADK::SessionService::Redis` for publishing. Redis clients can typically perform regular commands and publish.

**File: `lib/adk/session_service/redis.rb` (Conceptual Changes)**

```ruby
# ... other parts of ADK::SessionService::Redis ...

def append_event(session_id:, event:)
  return false unless event.is_a?(ADK::Event)
  session_key = redis_session_key(session_id)
  events_key = redis_events_key(session_id)
  return false unless @redis_client.exists?(session_key)
  session = get_session(session_id: session_id)
  return false unless session
  added_event = session.add_event(event)
  return false unless added_event

  max_retries = DEFAULT_MAX_RETRIES
  retries = 0
  success = false

  begin
    loop do
      @redis_client.watch(session_key) do
        # ... (existing logic to fetch current state if event.state_delta) ...
        # ... (logic to merge state delta with current state into session.state) ...

        results = @redis_client.multi do |multi|
          multi.rpush(events_key, JSON.generate(added_event.to_h))
          multi.hset(session_key, 'updated_at', session.updated_at.iso8601(3))
          multi.hset(session_key, 'state', JSON.generate(session.state_to_h))
          if @session_ttl&.positive?
            multi.expire(session_key, @session_ttl)
            multi.expire(events_key, @session_ttl)
          end
        end

        if results.nil? # Watch conflict
          retries += 1
          if retries >= max_retries
            ADK.logger.warn("Max retries (#{max_retries}) exceeded for session #{session_id} event append due to WATCH conflict.")
            @redis_client.unwatch rescue nil # Best effort
            return false # Indicate failure after retries
          end
          ADK.logger.debug("WATCH conflict for session #{session_id}, retrying (#{retries}/#{max_retries})...")
          next # Retry the loop
        end

        unless results.all?
          ADK.logger.error("Redis MULTI command failed during event append for session #{session_id}. Results: #{results.inspect}")
          return false # Indicate failure
        end
        
        success = true # Transaction succeeded
        break # Exit the loop
      end # end watch
    end # end loop
  rescue ::Redis::BaseError => e
    ADK.logger.error("Redis error appending event to session #{session_id}: #{e.class} - #{e.message}")
    @redis_client.unwatch rescue nil
    return false # Indicate failure
  end

  # --- NEW: Publish to Redis Pub/Sub if enabled and successful ---
  if success && ADK.config.enable_realtime_event_publishing # Check a global config flag
    begin
      channel = "adk:events:session:#{session_id}"
      payload = added_event.to_h.to_json
      published_clients = @redis_client.publish(channel, payload)
      ADK.logger.debug "Published event to Redis channel '#{channel}' (clients: #{published_clients}) for session '#{session_id}'"
    rescue ::Redis::BaseError => e
      ADK.logger.error "Redis Pub/Sub Error publishing event for session '#{session_id}': #{e.message}"
      # Don't let publishing failure fail the append_event operation itself
    end
  end
  # --- END NEW ---

  return success
end

# ... other methods ...
```

**2. Web Server: Streaming Endpoint (SSE or WebSockets)**

The `ADK::Web::App` would need a new endpoint that clients (browsers) can connect to for receiving these streamed events. Server-Sent Events (SSE) are often simpler for unidirectional server-to-client streaming.

**File: `lib/adk/web/app.rb` (or a new route module `lib/adk/web/routes/streaming_routes.rb`)**

```ruby
# ... existing requires ...
require 'sinatra/streaming' # For SSE

module ADK
  module Web
    # class App < Sinatra::Base
      # ... existing configure, initialize, helpers ...

      # --- NEW STREAMING ROUTE ---
      # Example using Server-Sent Events (SSE)
      # A client would connect to: GET /sessions/<session_id>/watch
      helpers Sinatra::Streaming
      
      get '/sessions/:session_id/watch', provides: 'text/event-stream' do |session_id_to_watch|
        # Optional: Add authentication/authorization here to ensure user can watch this session
        
        logger.info "SSE connection opened for session: #{session_id_to_watch}"
        redis_subscriber = nil # Initialize to ensure it's in scope for ensure block

        stream(:keep_open) do |out|
          begin
            # Create a NEW Redis client for this subscription, dedicated to blocking on SUBSCRIBE
            redis_subscriber = Redis.new(ADK.redis_options || {}) 
            channel = "adk:events:session:#{session_id_to_watch}"

            # Send an initial event to confirm connection (optional)
            out << "event: connected\ndata: #{JSON.generate({ message: "Watching session #{session_id_to_watch}" })}\n\n"
            
            redis_subscriber.subscribe(channel) do |on|
              on.message do |_ch, msg_payload|
                # Forward the message from Redis Pub/Sub to the SSE client
                logger.debug "SSE: Received event for session #{session_id_to_watch}: #{msg_payload.inspect}"
                out << "event: adk_event\ndata: #{msg_payload}\n\n"
                # Force flush if necessary, though Sinatra streaming usually handles this
                # out.flush 
              end
            end
          rescue ::Redis::BaseError => e
            logger.error "SSE stream: Redis subscription error for session #{session_id_to_watch}: #{e.message}"
            out << "event: error\ndata: #{JSON.generate({ error: "Redis subscription failed" })}\n\n"
            # No more messages will come, connection will be closed by client or server
          rescue IOError, ClientDisconnected => e # Standard errors if client disconnects
            logger.info "SSE stream: Client disconnected for session #{session_id_to_watch}. Error: #{e.class}"
            # No need to send to `out` as it's already closed/broken
          rescue StandardError => e
            logger.error "SSE stream: Unexpected error for session #{session_id_to_watch}: #{e.message}\n#{e.backtrace.join("\n")}"
            # Attempt to send an error event if the stream is still open
            out << "event: error\ndata: #{JSON.generate({ error: "Internal stream error" })}\n\n" rescue nil
          ensure
            logger.info "SSE stream: Closing for session #{session_id_to_watch}."
            # Clean up Redis subscription
            if redis_subscriber
              # Unsubscribe might not work if connection is broken, but try.
              # Forcing quit is more reliable to release the blocking subscribe.
              redis_subscriber.unsubscribe rescue nil 
              redis_subscriber.quit rescue nil # Force quit to close the connection
              logger.info "SSE stream: Unsubscribed and quit Redis for session #{session_id_to_watch}."
            end
            # `out.close` is handled by Sinatra when the block exits or an error not caught by ensure occurs
          end
        end # stream block
      end
      # --- END NEW STREAMING ROUTE ---
    # end # App class
  end
end
```

**3. Frontend JavaScript (in Web UI)**

On a page where you want to display the live agent work (e.g., the chat page, or a new "Agent Monitor" page):

```javascript
// Assuming 'currentSessionId' is available in the JavaScript scope
if (typeof EventSource !== 'undefined') {
  const source = new EventSource(`/sessions/${currentSessionId}/watch`); // Adjust path as per Sinatra route

  source.onopen = function(event) {
    console.log("SSE Connection Opened for session: " + currentSessionId);
    // You could update UI to show "Watching..."
  };

  source.addEventListener('adk_event', function(event) {
    console.log("Received ADK Event:", event.data);
    try {
      const eventData = JSON.parse(event.data);
      // Now, eventData is the deserialized ADK::Event hash (from event.to_h)
      // You would have JavaScript logic here to:
      // 1. Determine the event role (user, agent, tool_request, tool_result)
      // 2. Format the event content appropriately
      // 3. Append it to a "live feed" div on the page.
      // Example:
      const feedElement = document.getElementById('live-agent-feed'); // Assuming this div exists
      if (feedElement) {
        const item = document.createElement('div');
        item.className = 'feed-item event-role-' + eventData.role; // For styling
        
        let contentHtml = `<strong>${eventData.role}</strong>`;
        if (eventData.tool_name) {
          contentHtml += ` (Tool: ${eventData.tool_name})`;
        }
        contentHtml += `: <pre>${JSON.stringify(eventData.content, null, 2)}</pre>`;
        // Add timestamp if desired: new Date(eventData.timestamp).toLocaleTimeString()
        
        item.innerHTML = contentHtml;
        feedElement.appendChild(item);
        feedElement.scrollTop = feedElement.scrollHeight; // Auto-scroll
      }
    } catch (e) {
      console.error("Error parsing incoming ADK event data:", e);
    }
  });

  source.addEventListener('error', function(event) {
    if (event.target.readyState === EventSource.CLOSED) {
      console.log("SSE Connection Closed by server for session: " + currentSessionId);
      source.close(); // Ensure client-side cleanup
    } else if (event.target.readyState === EventSource.CONNECTING) {
      console.log("SSE Connection lost, attempting to reconnect for session: " + currentSessionId);
    } else {
      console.error("SSE Error for session " + currentSessionId + ":", event);
      // Maybe display an error to the user
    }
  });

  // Optional: Logic to close the EventSource when the user navigates away or closes the watch view
  // window.addEventListener('beforeunload', () => {
  //   if (source) {
  //     source.close();
  //   }
  // });

} else {
  console.log("Your browser doesn't support Server-Sent Events. Live watching disabled.");
  // Fallback or message to user
}
```

**Configuration (New Option):**

**File: `lib/adk/configuration.rb`** (or a new `lib/adk/configuration/realtime.rb`)

```ruby
# ...
module ADK
  class Configuration
    # ... (existing attributes) ...
    
    # @return [Boolean] Whether to publish ADK events to Redis Pub/Sub for real-time watching.
    attr_accessor :enable_realtime_event_publishing

    def initialize
      # ... (existing defaults) ...
      @enable_realtime_event_publishing = false # Default to off
      # ...
    end
  end
end
```

And in `lib/adk.rb` where `ADK.configure` is defined, you'd ensure this new option can be set.

**Summary of Changes:**

1.  **`ADK::SessionService::Redis`**: Modified `append_event` to publish the event to a Redis channel if a global config flag is enabled.
2.  **`ADK::Web::App` (or new route module)**: Added an SSE endpoint (e.g., `/sessions/:session_id/watch`) that:
    *   Creates a dedicated Redis client for `SUBSCRIBE`.
    *   Subscribes to the specific session's event channel.
    *   Streams received messages to the connected browser client using SSE format.
    *   Handles client disconnects to clean up the Redis subscription.
3.  **Web UI (JavaScript)**: Added client-side JavaScript to connect to the SSE endpoint using `EventSource`, listen for custom `adk_event`s, parse the JSON data, and dynamically update the DOM to display the event flow.
4.  **Configuration**: Added `ADK.config.enable_realtime_event_publishing`.

This provides a robust mechanism for real-time agent activity streaming to the browser. WebSockets would follow a similar pattern but with different connection management on both server and client. SSE is generally a good starting point for this kind of unidirectional data flow.