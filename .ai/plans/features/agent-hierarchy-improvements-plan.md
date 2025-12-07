# PRD: Agent Hierarchy & MAS Improvements

## 1. Product overview

### 1.1 Document title and version

- PRD: Agent Hierarchy & Multi-Agent System Improvements
- Version: 1.0
- Date: December 7, 2025

### 1.2 Product summary

This PRD addresses the gaps in the ADK-Ruby multi-agent system (MAS) implementation. After a thorough codebase review, the majority of the original recommendations have already been implemented. This plan focuses on the **remaining gaps** that need attention.

The core workflow agents (`SequentialAgent`, `ParallelAgent`, `LoopAgent`) are fully functional, Redis persistence supports hierarchical definitions, and the Web UI can display/edit agent hierarchies. However, several important features remain incomplete.

## 2. Goals

### 2.1 Business goals

- Complete the multi-agent system feature set for production readiness
- Enable complex agent workflows with proper escalation/termination signals
- Provide comprehensive documentation for developers adopting MAS patterns

### 2.2 User goals

- Developers can build sophisticated multi-agent workflows with clear escalation paths
- Developers have complete documentation and examples for all MAS patterns
- Visual workflow configuration in the Web UI is intuitive

### 2.3 Non-goals

- Major architectural changes to existing workflow agents (they work well)
- Rewriting the Redis storage layer (already handles all fields)
- Adding new agent types beyond Sequential/Parallel/Loop

## 3. Current state analysis

### 3.1 What's already implemented ✅

| Component | Status | Location |
|-----------|--------|----------|
| `SequentialAgent` | Complete | `lib/adk/agents/sequential_agent.rb` |
| `ParallelAgent` | Complete | `lib/adk/agents/parallel_agent.rb` |
| `LoopAgent` | Complete | `lib/adk/agents/loop_agent.rb` |
| `parent_agent` / `sub_agents` attributes | Complete | `lib/adk/agent.rb` |
| `output_key` state management | Complete | All workflow agents |
| `delegation_targets` / `can_delegate_to` | Complete | `lib/adk/agent.rb`, `lib/adk/planner.rb` |
| Redis persistence for hierarchy | Complete | `lib/adk/definition_store/redis_store.rb` |
| Web UI hierarchy display/edit | Complete | `lib/adk/web/views/_display_agent_hierarchy.slim` |
| Agent hierarchy tests | Partial | `spec/adk/agent_hierarchy_spec.rb` |
| Delegation planner tests | Partial | `spec/adk/planner_delegation_spec.rb` |

### 3.2 What's missing/incomplete ❌

| Gap | Priority | Impact |
|-----|----------|--------|
| Event `actions` field for escalation | High | Loop termination, error escalation |
| Comprehensive workflow agent tests | Medium | Test coverage |
| MAS documentation | Medium | Developer adoption |
| Visual workflow builder UI | Low | UX improvement |

## 4. Functional requirements

### 4.1 Event escalation system (Priority: High)

- **Add `actions` attribute to `ADK::Event`**
  - Support `{ escalate: true, reason: "..." }` pattern
  - Maintain backward compatibility with existing events
  - Update `to_h` and `from_h` serialization methods
  - Workflow agents should check `actions[:escalate]` to terminate early

### 4.2 Test coverage expansion (Priority: Medium)

- **Add dedicated specs for workflow agents:**
  - `spec/adk/agents/sequential_agent_spec.rb`
  - `spec/adk/agents/parallel_agent_spec.rb`
  - `spec/adk/agents/loop_agent_spec.rb`
- **Test scenarios:**
  - Happy path execution
  - Error propagation
  - Early termination via escalation
  - State passing between agents
  - Timeout handling (ParallelAgent)
  - Loop condition termination (LoopAgent)

### 4.3 Documentation (Priority: Medium)

- **Create/complete documentation:**
  - `public/docs/multi_agent_systems.md` - Overview and concepts
  - `public/docs/workflow_agents.md` - SequentialAgent, ParallelAgent, LoopAgent
  - `public/docs/agent_delegation.md` - Dynamic task delegation
  - `public/docs/mas_patterns.md` - Common patterns and best practices

### 4.4 Web UI workflow builder enhancement (Priority: Low)

- **Current state:** Simple multi-select for sub-agents
- **Enhancement:** Visual drag-and-drop workflow builder
  - Reorderable list for sequential agents
  - Visual connection lines showing flow
  - Inline preview of agent details

## 5. User experience

### 5.1 Entry points & first-time user flow

- Developers discover MAS through documentation
- Simple examples demonstrate core concepts
- Web UI allows experimentation without code

### 5.2 Core experience

- **Step 1**: Define specialized agents with `output_key`
- **Step 2**: Create workflow agent (Sequential/Parallel/Loop)
- **Step 3**: Configure sub-agents and their execution order
- **Step 4**: Run workflow and observe state propagation

### 5.3 Advanced features & edge cases

- Custom escalation conditions in LoopAgent
- Error recovery strategies in ParallelAgent
- Nested workflows (workflow agent containing another workflow agent)

## 6. Technical considerations

### 6.1 Event actions implementation

```ruby
# Proposed change to lib/adk/event.rb
Event = Struct.new(:role, :content, :timestamp, :tool_name, :state_delta, :event_id, :actions, keyword_init: true) do
  def initialize(role:, content:, timestamp: nil, tool_name: nil, state_delta: nil, event_id: nil, actions: nil)
    # ... existing validation ...
    
    # Validate actions is a Hash or nil
    unless actions.nil? || actions.is_a?(Hash)
      ADK.logger.warn("Event: :actions must be a Hash or nil, received #{actions.class}.")
      actions = nil
    end
    
    super(
      # ... existing fields ...
      actions: actions&.transform_keys(&:to_sym)
    )
    freeze
  end
  
  # Helper to check if escalation is requested
  def escalate?
    actions&.dig(:escalate) == true
  end
end
```

### 6.2 Integration points

- LoopAgent checks `event.escalate?` after each sub-agent execution
- SequentialAgent can optionally stop on escalation
- ParallelAgent aggregates escalation signals from parallel executions

## 7. Milestones & sequencing

### 7.1 Project estimate

- Small-Medium: 1-2 weeks

### 7.2 Suggested phases

- **Phase 1: Event Escalation** (2-3 days)
  - Add `actions` to Event
  - Update workflow agents to check escalation
  - Add tests

- **Phase 2: Test Coverage** (2-3 days)
  - Create comprehensive workflow agent specs
  - Test all edge cases

- **Phase 3: Documentation** (2-3 days)
  - Write MAS documentation
  - Create additional examples
  - Update existing docs to reference MAS

- **Phase 4: UI Enhancement** (Optional, 3-5 days)
  - Visual workflow builder
  - Drag-and-drop ordering

## 8. User stories

### 8.1 Event escalation

- **ID**: US-001
- **Description**: As a developer, I want my LoopAgent to terminate early when a sub-agent signals completion, so that I don't waste resources on unnecessary iterations.
- **Acceptance Criteria**:
  - `ADK::Event` has an `actions` attribute
  - Events can be created with `actions: { escalate: true, reason: "..." }`
  - `LoopAgent` terminates when receiving an event with `escalate: true`
  - Escalation reason is included in final result

### 8.2 Workflow agent testing

- **ID**: US-002
- **Description**: As a developer contributing to ADK-Ruby, I want comprehensive tests for workflow agents, so that I can confidently make changes without breaking existing functionality.
- **Acceptance Criteria**:
  - Each workflow agent has its own spec file
  - Tests cover success, failure, and edge cases
  - Test coverage for workflow agents exceeds 90%

### 8.3 MAS documentation

- **ID**: US-003
- **Description**: As a developer new to ADK-Ruby, I want clear documentation on multi-agent systems, so that I can quickly understand and implement complex agent workflows.
- **Acceptance Criteria**:
  - Documentation explains MAS concepts
  - Each workflow agent type has usage examples
  - Common patterns are documented with code samples
  - Troubleshooting section addresses common issues





