# Advanced Features

## Agent Delegation

Agents can dynamically delegate tasks to other specialized agents during execution. This allows an agent to "ask for help" or hand off a sub-task.

### Configuration

Use `can_delegate_to` to specify which agents are available for delegation.

```ruby
ADK::Agent.define do |agent|
  agent.name :manager
  agent.instruction "Manage the project and delegate tasks."
  
  # Allow delegation to these agents
  agent.can_delegate_to :researcher, :coder
end
```

### How it Works

1.  **Planning**: The `ADK::Planner` sees the available delegation targets as "tools" (e.g., `agent_transfer_to_researcher`).
2.  **Execution**: If the agent decides to delegate, it invokes the delegation tool.
3.  **Transfer**: The `ADK::Agent` intercepts this call and executes the target agent with the specified task.
4.  **Session Reuse**: By default, delegation creates a new isolated session. To share state, the `use_calling_session` parameter can be used (configured internally or via tool options).

## Callbacks

You can hook into the agent's lifecycle to execute custom logic.

```ruby
ADK::Agent.define do |agent|
  # ...
  
  agent.before_agent_callback do |context|
    ADK.logger.info "Agent starting for session #{context.session_id}"
  end
  
  agent.after_tool_callback do |tool, params, context, result|
    # Modify result or log execution
    ADK.logger.info "Tool #{tool.name} executed."
  end
end
```

Available callbacks:
- `before_agent_callback`
- `after_agent_callback`
- `before_model_callback`
- `after_model_callback`
- `before_tool_callback`
- `after_tool_callback`
