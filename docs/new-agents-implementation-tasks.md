# Multi-Agent System (MAS) Implementation Tasks

This document breaks down the implementation plan into concrete tasks. Each task is marked with its dependencies and status.

## Phase 1: Core Agent Hierarchy

### Task Group 1.1: Basic Agent Hierarchy
- [] Add `parent_agent` attribute to `ADK::Agent`
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [] Add `sub_agents` attribute to `ADK::Agent`
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [] Implement `ADK::Agent#initialize` sub-agents logic
  - File: `lib/adk/agent.rb`
  - Dependencies: `parent_agent` and `sub_agents` attributes
- [] Add hierarchy navigation methods to `ADK::Agent`
  - File: `lib/adk/agent.rb`
  - Dependencies: `parent_agent` and `sub_agents` attributes
  - Sub-tasks:
    - [] Implement `find_sub_agent(name_sym)`
    - [] Implement `root_agent`
    - [] Implement `find_agent(name_sym)` and `_find_agent_recursive`
- [] Add tests for agent hierarchy
  - File: `spec/adk/agent_spec.rb`
  - Dependencies: All above agent hierarchy changes

### Task Group 1.2: Definition Store Integration
- [] Add `sub_agent_names` to `ADK::AgentDefinition`
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [] Add `sub_agents_define` DSL method to `DefinitionProxy`
  - File: `lib/adk/agent.rb`
  - Dependencies: `sub_agent_names` attribute
- [] Implement `ADK::AgentDefinition.from_hash`
  - File: `lib/adk/agent.rb`
  - Dependencies: All new attributes
- [] Update `ADK::DefinitionStore::RedisStore`
  - File: `lib/adk/definition_store/redis_store.rb`
  - Dependencies: `sub_agent_names` attribute
  - Sub-tasks:
    - [] Add `sub_agent_names` to `AGENT_DEFINITION_FIELDS`
    - [] Update `save_definition`
    - [] Update `get_definition`
    - [] Update `update_definition`
- [] Add tests for definition store changes
  - Files:
    - `spec/adk/agent_definition_spec.rb`
    - `spec/adk/definition_store/redis_store_spec.rb`
  - Dependencies: All definition store changes

### Task Group 1.3: State Management
- [] Add `output_key` to `ADK::AgentDefinition`
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [] Add `output_key` DSL method to `DefinitionProxy`
  - File: `lib/adk/agent.rb`
  - Dependencies: `output_key` attribute
- [] Add `output_key` to `ADK::Agent`
  - File: `lib/adk/agent.rb`
  - Dependencies: Definition changes
- [] Modify `ADK::Agent#run_task` for state saving
  - File: `lib/adk/agent.rb`
  - Dependencies: `output_key` attribute
- [] Update Redis store for `output_key`
  - File: `lib/adk/definition_store/redis_store.rb`
  - Dependencies: `output_key` attribute
- [] Add tests for state management
  - Files:
    - `spec/adk/agent_spec.rb`
    - `spec/adk/agent_definition_spec.rb`
  - Dependencies: All state management changes

## Phase 2: Workflow Agents

### Task Group 2.0: Agent Type Support
- [ ] Add `agent_type` to `ADK::AgentDefinition`
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [ ] Add `agent_type` DSL method to `DefinitionProxy`
  - File: `lib/adk/agent.rb`
  - Dependencies: `agent_type` attribute
- [ ] Update definition store for `agent_type`
  - File: `lib/adk/definition_store/redis_store.rb`
  - Dependencies: `agent_type` attribute
- [ ] Add tests for agent type support
  - Files:
    - `spec/adk/agent_definition_spec.rb`
    - `spec/adk/definition_store/redis_store_spec.rb`
  - Dependencies: All agent type changes

### Task Group 2.1: Directory Structure
- [ ] Create `lib/adk/agents/` directory
- [ ] Create `lib/adk/agents.rb` manifest
  - Dependencies: None
- [ ] Update `lib/adk.rb` to require agents
  - Dependencies: Manifest file

### Task Group 2.2: Sequential Agent
- [ ] Create `SequentialAgent` class
  - File: `lib/adk/agents/sequential_agent.rb`
  - Dependencies: Core agent hierarchy
- [ ] Add sequential workflow DSL
  - File: `lib/adk/agent.rb`
  - Dependencies: `agent_type` support
- [ ] Implement `SequentialAgent#initialize`
  - Dependencies: Sequential workflow DSL
- [ ] Implement `SequentialAgent#run_task`
  - Dependencies: `initialize` implementation
- [ ] Add tests for sequential agent
  - File: `spec/adk/agents/sequential_agent_spec.rb`
  - Dependencies: All sequential agent changes

### Task Group 2.3: Parallel Agent
- [ ] Create `ParallelAgent` class
  - File: `lib/adk/agents/parallel_agent.rb`
  - Dependencies: Core agent hierarchy
- [ ] Add parallel workflow DSL
  - File: `lib/adk/agent.rb`
  - Dependencies: `agent_type` support
- [ ] Implement `ParallelAgent#initialize`
  - Dependencies: Parallel workflow DSL
- [ ] Implement `ParallelAgent#run_task`
  - Dependencies: `initialize` implementation
- [ ] Add tests for parallel agent
  - File: `spec/adk/agents/parallel_agent_spec.rb`
  - Dependencies: All parallel agent changes
- [ ] Document output_key requirements
  - Dependencies: Parallel agent implementation

### Task Group 2.4: Loop Agent
- [ ] Create `LoopAgent` class
  - File: `lib/adk/agents/loop_agent.rb`
  - Dependencies: Core agent hierarchy
- [ ] Add loop workflow DSL methods
  - File: `lib/adk/agent.rb`
  - Dependencies: `agent_type` support
  - Sub-tasks:
    - [ ] `loop_sub_agents`
    - [ ] `loop_max_iterations`
    - [ ] `loop_condition_state_key`
    - [ ] `loop_condition_expected_value`
- [ ] Implement `LoopAgent#initialize`
  - Dependencies: Loop workflow DSL
- [ ] Implement `LoopAgent#run_task`
  - Dependencies: `initialize` implementation
- [ ] Add tests for loop agent
  - File: `spec/adk/agents/loop_agent_spec.rb`
  - Dependencies: All loop agent changes

### Task Group 2.5: Event System
- [ ] Add `actions` to `ADK::Event`
  - File: `lib/adk/event.rb`
  - Dependencies: None
- [ ] Update event serialization
  - File: `lib/adk/event.rb`
  - Dependencies: `actions` attribute
- [ ] Add tests for event changes
  - File: `spec/adk/event_spec.rb`
  - Dependencies: All event changes

## Phase 3: Advanced Interaction

### Task Group 3.1: Agent Delegation
- [ ] Add `delegation_targets` to `ADK::AgentDefinition`
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [ ] Add `can_delegate_to` DSL method
  - File: `lib/adk/agent.rb`
  - Dependencies: `delegation_targets` attribute
- [ ] Update planner prompt for delegation
  - File: `lib/adk/planner.rb`
  - Dependencies: Delegation DSL
- [ ] Modify `ADK::Agent#execute_plan` for transfers
  - File: `lib/adk/agent.rb`
  - Dependencies: All delegation changes
- [ ] Add tests for delegation
  - Files:
    - `spec/adk/agent_spec.rb`
    - `spec/adk/planner_spec.rb`
  - Dependencies: All delegation changes

### Task Group 3.2: Agent Tool Enhancement
- [ ] Add `use_calling_session` parameter
  - File: `lib/adk/tools/agent_tool.rb`
  - Dependencies: None
- [ ] Update `perform_execution` for session handling
  - File: `lib/adk/tools/agent_tool.rb`
  - Dependencies: `use_calling_session` parameter
- [ ] Modify `ADK::Agent#initialize` for session service
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [ ] Add tests for agent tool changes
  - Files:
    - `spec/adk/tools/agent_tool_spec.rb`
    - `spec/adk/agent_spec.rb`
  - Dependencies: All agent tool changes

## Phase 4: Documentation & Examples

### Task Group 4.1: Core Documentation
- [ ] Document agent hierarchy
  - Files in `docs/core_concepts/`
  - Dependencies: Phase 1 implementation
- [ ] Document state management
  - Files in `docs/core_concepts/`
  - Dependencies: Phase 1 implementation
- [ ] Document workflow agents
  - Files in `docs/core_concepts/`
  - Dependencies: Phase 2 implementation
- [ ] Document advanced features
  - Files in `docs/core_concepts/`
  - Dependencies: Phase 3 implementation

### Task Group 4.2: Examples
- [ ] Create basic hierarchy examples
  - Files in `examples/`
  - Dependencies: Phase 1 implementation
- [ ] Create workflow examples
  - Files in `examples/`
  - Dependencies: Phase 2 implementation
- [ ] Create advanced interaction examples
  - Files in `examples/`
  - Dependencies: Phase 3 implementation

## Phase 5: Web UI

### Task Group 5.1: Agent List View
- [ ] Update agent list to show types
  - File: `lib/adk/web/views/agents.slim`
  - Dependencies: `agent_type` support

### Task Group 5.2: Agent Detail View
- [ ] Show parent/child relationships
  - File: `lib/adk/web/views/agent.slim`
  - Dependencies: Core hierarchy implementation
- [ ] Display workflow configurations
  - File: `lib/adk/web/views/agent.slim`
  - Dependencies: Workflow agent implementations

### Task Group 5.3: Agent Creation/Edit
- [ ] Add agent type selection
  - Files in `lib/adk/web/views/`
  - Dependencies: `agent_type` support
- [ ] Add workflow configuration UI
  - Files in `lib/adk/web/views/`
  - Dependencies: Workflow agent implementations
- [ ] Add sub-agent selection/ordering
  - Files in `lib/adk/web/views/`
  - Dependencies: Core hierarchy implementation

### Task Group 5.4: Tests
- [ ] Add tests for UI changes
  - Files in `spec/adk/web/`
  - Dependencies: All UI changes 