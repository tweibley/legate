# State Management

The ADK provides a robust state management system to share data between agents and persist execution context across sessions.

## Session State

Every agent execution happens within a `Session`. The session maintains:
- **Event History**: A log of all interactions (user messages, agent responses, tool calls).
- **State**: A key-value store for persisting data.

## Output Keys

Agents can automatically store their final result into the session state using the `output_key` definition.

```ruby
ADK::Agent.define do |agent|
  agent.name :researcher
  # ...
  agent.output_key :research_summary # Result will be saved to state key :research_summary
end
```

When this agent finishes execution, its result is saved to the session state under `:research_summary`.

## Accessing State

### In Other Agents
Subsequent agents in a workflow (e.g., in a `SequentialAgent`) can access this state. The ADK automatically injects relevant state information or allows agents to query it.

### In Tools
Tools can access the session state via the `ADK::ToolContext`.

```ruby
def perform_execution(params, context)
  # Read from state
  previous_result = context.state_get(:research_summary)
  
  # Write to state (pending until tool completion)
  context.state_set(:new_data, "value")
  
  # ...
end
```

## Session Service

The `ADK::SessionService` (e.g., `RedisStore` or `InMemory`) handles the actual storage and retrieval of state, ensuring persistence across agent invocations if a persistent store is configured.
