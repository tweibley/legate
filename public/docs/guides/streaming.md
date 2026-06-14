# Streaming agent events

An agent task can take many seconds — it may call several tools before it
answers. Rather than block until the final result, you can **stream the agent's
lifecycle events as they happen**: the user message, each tool request, each tool
result, and the final answer. This is how you build a responsive "thinking…
calling search… answering" experience instead of a frozen spinner.

## `on_event` — the streaming callback

`Agent#run_task` accepts an optional `on_event:` proc. It's called with each
`Legate::Event` the moment it's appended to the session, while the task runs:

```ruby
agent.run_task(
  session_id: session.id,
  user_input: 'Find the population of France and double it',
  session_service: session_service,
  on_event: ->(event) do
    case event.role
    when :user         then puts "▶ #{event.content}"
    when :tool_request then puts "  → calling #{event.tool_name}"
    when :tool_result  then puts "  ← #{event.content[:result]}"
    when :agent        then puts "✓ #{event.content[:result]}"
    end
  end
)
```

The events you'll see, in order:

| `event.role`   | When | `event.content` |
|----------------|------|-----------------|
| `:user`        | task starts | the user input string |
| `:tool_request`| before each tool runs | the params; `event.tool_name` is the tool |
| `:tool_result` | after each tool runs | `{ status:, result: / error_message: }` |
| `:agent`       | task finishes | the final result hash |

`on_event` is **purely additive**: the method still returns the final `Event`, and
omitting `on_event` leaves behavior exactly as before. It works for both the
default plan-then-execute strategy and the [agentic `:react` loop](agentic_agents)
— every event flows through the same session funnel.

### How it works

Every event an agent produces is persisted through `SessionService#append_event`.
The service broadcasts each appended event to subscribers of that session
(`EventBroadcast`), and `run_task` subscribes your `on_event` for the duration of
the run, tearing the subscription down afterward. Delivery is synchronous and
in order on the running thread, so a streaming HTTP response can write each frame
as it arrives.

## Server-Sent Events over HTTP

The web app exposes the stream as SSE:

```
POST /agents/:name/stream     (form field: message=…, plus the CSRF token)
Content-Type: text/event-stream
```

Each appended event is sent as an `event: message` frame; the run ends with an
`event: done` frame carrying the final result (or `event: error`):

```
event: message
data: {"role":"user","content":"double the population of France",…}

event: message
data: {"role":"tool_request","tool_name":"search","content":{…},…}

event: message
data: {"role":"tool_result","content":{"status":"success","result":"67 million"},…}

event: done
data: {"role":"agent","content":{"status":"success","result":"134 million"},…}
```

The frame payloads are `Event#to_h` (JSON, ISO-8601 timestamps). Because the
endpoint is CSRF-protected it can't be consumed by a bare `EventSource` (which is
GET-only and can't send the token); use `fetch` with a streaming reader:

```js
const res = await fetch(`/agents/${name}/stream`, {
  method: 'POST',
  headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({ message }),
});
const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
for (;;) {
  const { value, done } = await reader.read();
  if (done) break;
  // parse SSE frames out of `value`…
}
```

Each request runs as a fresh one-shot session.

## Scope: steps, not tokens

Streaming here is **step/event** level — you get each tool call and result as it
happens. Legate agents always plan and call tools rather than emitting free-form
model prose, and in the agentic loop the final answer arrives whole inside one
decision, so there's no separate token stream to forward. Token-level streaming
is a possible future addition (an adapter `supports_streaming?` capability); it
isn't needed to solve the "no feedback during a long run" problem, which event
streaming already does.

## Related

- [Agentic Agents](agentic_agents) — multi-step runs where streaming shines.
- [Legate Planner](../core_concepts/legate_planner) — what produces the steps.
