# Agent Hierarchy

The Legate supports a hierarchical agent structure, allowing agents to be composed of other agents (sub-agents). This enables the creation of complex systems where a parent agent coordinates the work of specialized child agents.

## Core Concepts

### Parent and Sub-Agents

- **Parent Agent**: An agent that contains and manages other agents.
- **Sub-Agent**: An agent that is managed by another agent. A sub-agent can also be a parent to other agents, creating a multi-level hierarchy.

### Definition

You can define sub-agents within an `Legate::AgentDefinition` using the `sub_agents_define` DSL method.

```ruby
Legate::Agent.define do |agent|
  agent.name :parent_agent
  agent.description "A parent agent that manages sub-agents"
  agent.instruction "You are a manager. Delegate tasks to your sub-agents."
  
  # Define sub-agents by name
  agent.sub_agents_define :researcher_agent, :writer_agent
end
```

The sub-agents must be defined and registered in the `GlobalDefinitionRegistry` so they can be instantiated when the parent agent is initialized.

## Runtime Structure

When a parent agent is initialized, it attempts to instantiate its defined sub-agents.

- **`agent.sub_agents`**: Returns a collection of initialized sub-agent instances.
- **`agent.parent_agent`**: Returns the parent agent instance (if any).
- **`agent.root_agent`**: Returns the top-level agent in the hierarchy.

### Navigation

You can navigate the hierarchy at runtime:

- **`agent.find_sub_agent(name)`**: Finds a direct sub-agent by name.
- **`agent.find_agent(name)`**: Finds an agent anywhere in the hierarchy (depth-first search).

## Usage

Hierarchies are fundamental to **Workflow Agents** (Sequential, Parallel, Loop) and **Delegation**.

- **Workflow Agents**: Use sub-agents as steps in a predefined process.
- **Delegation**: Uses sub-agents (or other agents in the hierarchy) as targets for dynamic task delegation.
