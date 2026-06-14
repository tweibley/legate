# Agent Delegation in Legate

## Overview

Agent delegation is a powerful feature in Legate that allows one agent to dynamically transfer control to another specialized agent during execution. This enables complex workflows where a coordinator agent can make decisions about which specialized agent should handle a particular task.

Unlike the `AgentTool` approach, which creates a new isolated session for the target agent, delegation maintains the same session context. This ensures continuity and allows agents to share state through the session.

## Key Concepts

### Delegation Targets

For an agent to delegate to another agent, the target agents must be explicitly defined as "delegation targets" in the delegating agent's definition:

```ruby
coordinator_agent = Legate::Agent.define do |a|
  a.name :coordinator_agent
  a.description 'A coordinator agent that delegates tasks'
  a.instruction 'You are a coordinator. Analyze tasks and delegate to specialists.'
  
  # Define which agents this agent can delegate to
  a.can_delegate_to :math_agent, :research_agent, :translation_agent
  
  # ... other configuration ...
end
```

### Agent Hierarchy

Delegation works within the agent hierarchy. An agent can:

1. **Delegate to direct sub-agents**: When agents are organized in a parent-child relationship.
2. **Delegate to any agent in the hierarchy**: By searching up and down the agent tree.
3. **Delegate to registered agents**: Even agents not directly in the hierarchy can be delegated to if their definitions are registered globally.

### Session State Continuity

When delegation occurs:

- The same session ID is used across all agents
- The session state is shared, allowing agents to read and write state
- The `output_key` feature can be used by each agent to store its results in the session state

## Implementation Methods

### 1. LLM-Driven Delegation

The primary way delegation happens is through the LLM planner, which can generate plan steps with special "agent_transfer_to_X" tool names:

```json
{
  "thought_process": "This is a math question, should delegate to math agent",
  "plan": [
    {
      "step": 1,
      "type": "tool_use",
      "tool_name": "agent_transfer_to_math_agent",
      "tool_input": {
        "task": "Calculate the square root of 144"
      },
      "reason": "This is a mathematical calculation"
    }
  ]
}
```

When the agent executes this plan, it recognizes the `agent_transfer_to_` prefix and performs delegation to the specified agent.

### 2. Direct Transfer Method

You can also programmatically delegate using the `transfer_to` method:

```ruby
result = agent.transfer_to(
  :math_agent,           # Target agent name
  "Calculate 2 + 2",     # Task to delegate
  session_id,            # Current session ID
  session_service        # Session service instance
)
```

This returns a standard result hash:

```ruby
{
  status: :success,
  target_agent: "math_agent",
  result: { status: :success, result: "4" }
}
```

## Code Examples

### Basic Delegation Setup

```ruby
# Define a math specialist agent
math_agent = Legate::Agent.define do |a|
  a.name :math_agent
  a.description 'Specialized in calculations'
  a.instruction 'You are a math expert. Solve calculations accurately.'
  a.use_tool :calculate
  a.output_key :calculation_result
end

# Define a coordinator that can delegate to the math agent
coordinator = Legate::Agent.define do |a|
  a.name :coordinator
  a.description 'Coordinates tasks between agents'
  a.instruction 'Analyze the task and delegate to specialists.'
  a.can_delegate_to :math_agent
  a.use_tool :echo
end

# Create and link the agents
coordinator_instance = Legate::Agent.new(definition: coordinator)
math_instance = Legate::Agent.new(definition: math_agent)

# Establish parent-child relationship
math_instance.instance_variable_set(:@parent_agent, coordinator_instance)
coordinator_instance.instance_variable_set(:@sub_agents, [math_instance])

# Start the agents
coordinator_instance.start
math_instance.start

# Run a task that might be delegated
result = coordinator_instance.run_task(
  session_id: session_id,
  user_input: "What is 125 * 45?",
  session_service: session_service
)
```

### Working with Session State

```ruby
# The delegated agent can store its result in the session state
math_agent = Legate::Agent.define do |a|
  a.name :math_agent
  a.description 'Specialized in calculations'
  a.instruction 'You are a math expert. Solve calculations accurately.'
  a.use_tool :calculate
  a.output_key :calculation_result  # Will store results with this key
end

# Later, another agent can access this result
translator_agent = Legate::Agent.define do |a|
  a.name :translator_agent
  a.description 'Translates content'
  a.instruction <<~INSTRUCTION
    You are a translator. Translate text using the calculation results
    from the math agent if available in the session state.
  INSTRUCTION
  a.use_tool :translate
end
```

## Comparison: Delegation vs. AgentTool

| Feature | Agent Delegation | AgentTool |
|---------|-----------------|-----------|
| **Session Context** | Maintains the same session | Creates a new session |
| **State Sharing** | Shared session state | No state sharing, isolated execution |
| **Agent Registration** | Uses agent hierarchy and registry | Uses agent definitions from store |
| **Use Case** | Complex workflows with state continuity | Isolated, independent agent operations |
| **Implementation** | Direct `transfer_to` or LLM-driven | Tool execution via `tool_registry` |

## Best Practices

1. **Be Specific with Instructions**: Provide clear guidelines in your coordinator agent's instructions about when to delegate and which specialized agent to use for different tasks.

2. **Use `output_key`**: Have specialized agents store their results using the `output_key` feature to make them available in the session state.

3. **Validate Delegation Targets**: Ensure all agents defined in `can_delegate_to` actually exist. The system will warn you about missing targets, but it's best to address these warnings.

4. **Avoid Circular Delegation**: The system prevents direct circular dependencies, but complex cascading delegation chains should be avoided.

5. **Consider Agent Hierarchy**: Organize your agents in a logical hierarchy that reflects your delegation patterns, with coordinator agents at the top and specialists as sub-agents.

## Implementation Details

Under the hood, delegation is implemented through:

1. The `agent_transfer_to_` special tool name pattern recognized by `execute_step`
2. The `transfer_to` method that handles the delegation logic
3. Agent hierarchy navigation through `root_agent` and `find_agent` methods
4. Session state persistence across agent boundaries

For detailed implementation examples, see `examples/11_agent_delegation.rb` (and `examples/advanced/mas/proper_delegation_example.rb`) in the Legate codebase. 