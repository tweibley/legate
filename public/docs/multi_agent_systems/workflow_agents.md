# Workflow Agents

Workflow Agents are specialized agents designed to orchestrate other agents in specific patterns. They extend the base `ADK::Agent` class.

## Sequential Agent

Executes a list of sub-agents in a strict order. The output of one agent can be used as context for the next.

**Configuration:**
```ruby
ADK::Agent.define do |agent|
  agent.name :content_pipeline
  agent.agent_type :sequential
  agent.instruction "Process content."
  
  # Define execution order
  agent.sequential_sub_agents :researcher, :drafter, :editor
end
```

**Behavior:**
1.  Executes `:researcher`.
2.  Passes result to `:drafter`.
3.  Passes result to `:editor`.
4.  Returns the final result from `:editor`.

## Parallel Agent

Executes multiple sub-agents concurrently. Useful for independent tasks.

**Configuration:**
```ruby
ADK::Agent.define do |agent|
  agent.name :market_analysis
  agent.agent_type :parallel
  agent.instruction "Analyze market sectors."
  
  # Define agents to run in parallel
  agent.parallel_sub_agents :tech_analyst, :finance_analyst, :healthcare_analyst
end
```

**Behavior:**
1.  Starts all sub-agents simultaneously.
2.  Waits for all to complete.
3.  Returns a combined result containing outputs from all agents.

## Loop Agent

Executes a sub-agent (or a sequence of sub-agents) repeatedly until a condition is met or a maximum iteration count is reached.

**Configuration:**
```ruby
ADK::Agent.define do |agent|
  agent.name :refiner
  agent.agent_type :loop
  agent.instruction "Refine the text until it meets quality standards."
  
  agent.loop_sub_agents :editor
  
  # Stop after 5 iterations
  agent.loop_max_iterations 5
  
  # OR stop when state key :quality_approved is true
  agent.loop_condition :quality_approved, true
end
```

**Behavior:**
1.  Executes the sub-agents.
2.  Checks the loop condition (state key).
3.  Repeats if condition not met and max iterations not reached.
