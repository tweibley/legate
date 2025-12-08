# Multi-Agent System (MAS) Implementation Tasks

This document breaks down the implementation plan into concrete tasks. Each task is marked with its dependencies and status.

## Phase 1: Core Agent Hierarchy

### Task Group 1.1: Basic Agent Hierarchy
- [x] Add `parent_agent` attribute to `ADK::Agent`
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [x] Add `sub_agents` attribute to `ADK::Agent`
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [x] Implement `ADK::Agent#initialize` sub-agents logic
  - File: `lib/adk/agent.rb`
  - Dependencies: `parent_agent` and `sub_agents` attributes
- [x] Add hierarchy navigation methods to `ADK::Agent`
  - File: `lib/adk/agent.rb`
  - Dependencies: `parent_agent` and `sub_agents` attributes
  - Sub-tasks:
    - [x] Implement `find_sub_agent(name_sym)`
    - [x] Implement `root_agent`
    - [x] Implement `find_agent(name_sym)` and `_find_agent_recursive`
- [x] Add tests for agent hierarchy
  - File: `spec/adk/agent_spec.rb`
  - Dependencies: All above agent hierarchy changes

### Task Group 1.2: Definition Store Integration
- [x] Add `sub_agent_names` to `ADK::AgentDefinition`
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [x] Add `sub_agents_define` DSL method to `DefinitionProxy`
  - File: `lib/adk/agent.rb`
  - Dependencies: `sub_agent_names` attribute
- [x] Implement `ADK::AgentDefinition.from_hash`
  - File: `lib/adk/agent.rb`
  - Dependencies: All new attributes
- [x] Update `ADK::DefinitionStore::RedisStore`
  - File: `lib/adk/definition_store/redis_store.rb`
  - Dependencies: `sub_agent_names` attribute
  - Sub-tasks:
    - [x] Add `sub_agent_names` to `AGENT_DEFINITION_FIELDS`
    - [x] Update `save_definition`
    - [x] Update `get_definition`
    - [x] Update `update_definition`
- [x] Add tests for definition store changes
  - Files:
    - `spec/adk/agent_definition_spec.rb`
    - `spec/adk/definition_store/redis_store_spec.rb`
  - Dependencies: All definition store changes

### Task Group 1.3: State Management
- [x] Add `output_key` to `ADK::AgentDefinition`
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [x] Add `output_key` DSL method to `DefinitionProxy`
  - File: `lib/adk/agent.rb`
  - Dependencies: `output_key` attribute
- [x] Add `output_key` to `ADK::Agent`
  - File: `lib/adk/agent.rb`
  - Dependencies: Definition changes
- [x] Modify `ADK::Agent#run_task` for state saving
  - File: `lib/adk/agent.rb`
  - Dependencies: `output_key` attribute
- [x] Update Redis store for `output_key`
  - File: `lib/adk/definition_store/redis_store.rb`
  - Dependencies: `output_key` attribute
- [x] Add tests for state management
  - Files:
    - `spec/adk/agent_spec.rb`
    - `spec/adk/agent_definition_spec.rb`
  - Dependencies: All state management changes

## Phase 2: Workflow Agents

### Task Group 2.0: Agent Type Support
- [x] Add `agent_type` to `ADK::AgentDefinition`
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [x] Add `agent_type` DSL method to `DefinitionProxy`
  - File: `lib/adk/agent.rb`
  - Dependencies: `agent_type` attribute
- [x] Update definition store for `agent_type`
  - File: `lib/adk/definition_store/redis_store.rb`
  - Dependencies: `agent_type` attribute
- [x] Add tests for agent type support
  - Files:
    - `spec/adk/agent_definition_spec.rb`
    - `spec/adk/definition_store/redis_store_spec.rb`
  - Dependencies: All agent type changes

### Task Group 2.1: Directory Structure
- [x] Create `lib/adk/agents/` directory
- [x] Create `lib/adk/agents.rb` manifest
  - Dependencies: None
- [x] Update `lib/adk.rb` to require agents
  - Dependencies: Manifest file

### Task Group 2.2: Sequential Agent
- [x] Create `SequentialAgent` class
  - File: `lib/adk/agents/sequential_agent.rb`
  - Dependencies: Core agent hierarchy
- [x] Add sequential workflow DSL
  - File: `lib/adk/agent.rb`
  - Dependencies: `agent_type` support
- [x] Implement `SequentialAgent#initialize`
  - Dependencies: Sequential workflow DSL
- [x] Implement `SequentialAgent#run_task`
  - Dependencies: `initialize` implementation
- [x] Add tests for sequential agent
  - File: `spec/adk/agents/sequential_agent_spec.rb`
  - Dependencies: All sequential agent changes

### Task Group 2.3: Parallel Agent
- [x] Create `ParallelAgent` class
  - File: `lib/adk/agents/parallel_agent.rb`
  - Dependencies: Core agent hierarchy
- [x] Add parallel workflow DSL
  - File: `lib/adk/agent.rb`
  - Dependencies: `agent_type` support
- [x] Implement `ParallelAgent#initialize`
  - Dependencies: Parallel workflow DSL
- [x] Implement `ParallelAgent#run_task`
  - Dependencies: `initialize` implementation
- [x] Add tests for parallel agent
  - File: `spec/adk/agents/parallel_agent_spec.rb`
  - Dependencies: All parallel agent changes
- [x] Document output_key requirements
  - Dependencies: Parallel agent implementation

### Task Group 2.4: Loop Agent
- [x] Create `LoopAgent` class
  - File: `lib/adk/agents/loop_agent.rb`
  - Dependencies: Core agent hierarchy
- [x] Add loop workflow DSL methods
  - File: `lib/adk/agent.rb`
  - Dependencies: `agent_type` support
  - Sub-tasks:
    - [x] `loop_sub_agents`
    - [x] `loop_max_iterations`
    - [x] `loop_condition_state_key`
    - [x] `loop_condition_expected_value`
- [x] Implement `LoopAgent#initialize`
  - Dependencies: Loop workflow DSL
- [x] Implement `LoopAgent#run_task`
  - Dependencies: `initialize` implementation
- [x] Add tests for loop agent
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
- [x] Add `delegation_targets` to `ADK::AgentDefinition`
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [x] Add `can_delegate_to` DSL method
  - File: `lib/adk/agent.rb`
  - Dependencies: `delegation_targets` attribute
- [x] Update planner prompt for delegation
  - File: `lib/adk/planner.rb`
  - Dependencies: Delegation DSL
- [x] Modify `ADK::Agent#execute_plan` for transfers
  - File: `lib/adk/agent.rb`
  - Dependencies: All delegation changes
- [x] Add tests for delegation
  - Files:
    - `spec/adk/agent_spec.rb`
    - `spec/adk/planner_spec.rb`
  - Dependencies: All delegation changes

### Task Group 3.2: Agent Tool Enhancement
- [x] Add `use_calling_session` parameter
  - File: `lib/adk/tools/agent_tool.rb`
  - Dependencies: None
- [x] Update `perform_execution` for session handling
  - File: `lib/adk/tools/agent_tool.rb`
  - Dependencies: `use_calling_session` parameter
- [x] Modify `ADK::Agent#initialize` for session service
  - File: `lib/adk/agent.rb`
  - Dependencies: None
- [x] Add tests for agent tool changes
  - Files:
    - `spec/adk/tools/agent_tool_spec.rb`
    - `spec/adk/agent_spec.rb`
  - Dependencies: All agent tool changes

## Phase 4: Documentation & Examples

### Task Group 4.1: Core Documentation
- [x] Document agent hierarchy
  - Files in `docs/core_concepts/`
  - Dependencies: Phase 1 implementation
- [x] Document state management
  - Files in `docs/core_concepts/`
  - Dependencies: Phase 1 implementation
- [x] Document workflow agents
  - Files in `docs/core_concepts/`
  - Dependencies: Phase 2 implementation
- [x] Document advanced features
  - Files in `docs/core_concepts/`
  - Dependencies: Phase 3 implementation

### Task Group 4.2: Examples
- [x] Create basic hierarchy examples
  - Files in `examples/`
  - Dependencies: Phase 1 implementation
- [x] Create workflow examples
  - Files in `examples/`
  - Dependencies: Phase 2 implementation
- [x] Create advanced interaction examples
  - Files in `examples/`
  - Dependencies: Phase 3 implementation

## Phase 5: Web UI

### Task Group 5.1: Agent List View
- [x] Update agent list to show types
  - File: `lib/adk/web/views/agents.slim`
  - Dependencies: `agent_type` support

### Task Group 5.2: Agent Detail View
- [x] Show parent/child relationships
  - File: `lib/adk/web/views/agent.slim`
  - Dependencies: Core hierarchy implementation
- [x] Display workflow configurations
  - File: `lib/adk/web/views/agent.slim`
  - Dependencies: Workflow agent implementations

### Task Group 5.3: Agent Creation/Edit
- [x] Add agent type selection
  - Files in `lib/adk/web/views/`
  - Dependencies: `agent_type` support
- [x] Add workflow configuration UI
  - Files in `lib/adk/web/views/`
  - Dependencies: Workflow agent implementations
- [x] Add sub-agent selection/ordering
  - Files in `lib/adk/web/views/`
  - Dependencies: Core hierarchy implementation

### Task Group 5.4: Tests
- [ ] Add tests for UI changes
  - Files in `spec/adk/web/`
  - Dependencies: All UI changes 