# Dynamic Agent Transfer Implementation Plan

## Current State Assessment

The codebase currently has partial support for dynamic agent transfer:

- **AgentDefinition** class has:
  - `delegation_targets` attribute to store which agents can be delegated to
  - `can_delegate_to` DSL method in `DefinitionProxy` to define delegation targets
  - Serialization/deserialization in `to_h` and `from_hash`

- **Agent Hierarchy** support exists:
  - `root_agent` to find the topmost agent
  - `find_agent` to search recursively through the hierarchy
  - `find_sub_agent` to locate direct children
  - Circular dependency detection

- **Execution Flow** has initial support:
  - `execute_step` can detect tool names starting with "agent_transfer_to_"
  - Logic exists to extract target agent name and handle delegation
  - Basic logging and error handling implemented

## Missing Pieces

1. **Planner Updates**: 
   - The planner doesn't inject information about delegation targets into LLM prompts
   - No mechanism to instruct the LLM about available agents and delegation process

2. **Direct Agent Invocation**:
   - Current implementation uses `delegate_task` tool instead of direct `run_task` as originally designed
   - The approach is indirect and doesn't match the original design intention

3. **Target Agent Discovery**:
   - Code only searches for delegation targets among direct sub-agents using `find_sub_agent`
   - Need to support finding agents anywhere in the hierarchy

4. **Validation of Delegation Targets**:
   - No validation during definition to ensure delegation targets exist
   - No runtime validation before attempting delegation

5. **Testing**:
   - Lack of tests for agent delegation functionality
   - No integration tests for end-to-end delegation flow

## Implementation Plan

### Phase 1: Planner Integration

1. **Update Planner Prompt Construction**
   - File: `lib/adk/planner.rb`
   - Task: Modify `build_multi_step_gemini_prompt` to include delegation targets information
   - Add method to format delegation targets as pseudo-tools
   - Update prompt template to include delegation instructions

2. **Update Planner Output Handling**
   - File: `lib/adk/planner.rb`
   - Task: Enhance `validate_and_format_multi_step_plan` to handle agent delegation steps
   - Support conversion of planner output into proper agent transfer steps

### Phase 2: Direct Agent Invocation

1. **Implement Direct Agent Transfer Method**
   - File: `lib/adk/agent.rb`
   - Task: Add `transfer_to` instance method for direct agent delegation 
   - Support session context preservation during transfer
   - Implement comprehensive error handling and logging

2. **Update Execute Step for Direct Invocation**
   - File: `lib/adk/agent.rb`
   - Task: Refactor `execute_step` to use direct invocation rather than tool delegation
   - Use `root_agent.find_agent` to locate agents anywhere in hierarchy
   - Maintain session continuity during delegation

### Phase 3: Validation & Safety

1. **Add Definition-time Validation**
   - File: `lib/adk/agent.rb` (DefinitionProxy class)
   - Task: Enhance `can_delegate_to` method to validate target agents exist
   - Add warnings for missing targets during definition

2. **Add Runtime Validation**
   - File: `lib/adk/agent.rb`
   - Task: Add pre-execution validation in `execute_step` or `transfer_to`
   - Verify target agent exists and is accessible before delegation
   - Implement proper error handling for unreachable agents

### Phase 4: Testing

1. **Unit Tests for Delegation Definition**
   - File: `spec/adk/agent_definition_delegation_spec.rb`
   - Test serialization/deserialization of delegation targets
   - Test DSL `can_delegate_to` method
   - Test validation of delegation targets

2. **Unit Tests for Delegation Planner Integration**
   - File: `spec/adk/planner_delegation_spec.rb`
   - Test `format_delegation_targets` method
   - Test delegation information inclusion in prompts
   - Test plan validation and step conversion

3. **Unit Tests for Agent Transfer Execution**
   - File: `spec/adk/agent_transfer_spec.rb`
   - Test direct delegation between agents
   - Test hierarchy traversal for finding delegation targets
   - Test error handling during delegation

4. **Integration Tests**
   - File: `spec/integration/agent_delegation_spec.rb`
   - Test end-to-end delegation flow
   - Test session state persistence across delegation
   - Test complex delegation scenarios (nested, chained)

### Phase 5: Documentation

1. **Update API Documentation**
   - Update inline documentation for all modified methods
   - Add examples of delegation usage in method documentation

2. **User Guide for Agent Delegation**
   - Create `public/docs/multi_agent_systems/agent_delegation.md`
   - Document delegation pattern with examples
   - Explain delegation vs. agent tools differences

3. **Code Examples**
   - Add example in `examples/mas/delegation_example.rb`
   - Demonstrate delegation pattern in real code

## Implementation Timeline

- **Phase 1**: 2 days
- **Phase 2**: 2 days  
- **Phase 3**: 1 day
- **Phase 4**: 3 days
- **Phase 5**: 2 days

**Total Estimated Time**: 10 working days

## Progress Tracking

- [x] Phase 1: Planner Integration
  - [x] Update `build_multi_step_gemini_prompt`
  - [x] Add delegation formatting method
  - [x] Update prompt template
  - [x] Update plan validation

- [x] Phase 2: Direct Agent Invocation
  - [x] Implement `transfer_to` method
  - [x] Refactor `execute_step`
  - [x] Add hierarchy traversal support
  - [x] Implement session continuity

- [x] Phase 3: Validation & Safety
  - [x] Enhance `can_delegate_to` validation
  - [x] Add runtime validation
  - [x] Implement error handling

- [x] Phase 4: Testing
  - [x] Agent definition delegation tests
  - [x] Planner delegation tests
  - [x] Agent transfer tests
  - [x] Integration tests

- [x] Phase 5: Documentation
  - [x] Update API documentation
  - [x] Create user guide
  - [x] Add code examples

## Summary of Implementation

We've successfully implemented the dynamic agent transfer feature:

1. **Planner Integration**:
   - Enhanced the planner to include delegation targets as tools in prompts
   - Added specific instructions to guide the LLM on delegation decision-making
   - Added support for processing delegation steps in plan validation

2. **Direct Agent Transfer**:
   - Implemented the `transfer_to` method for direct agent delegation
   - Updated `execute_step` to support special "agent_transfer_to_" tools
   - Implemented hierarchical agent discovery

3. **Validation & Safety**:
   - Added validation in `can_delegate_to` to warn about missing targets
   - Added runtime validation before delegation attempts
   - Implemented comprehensive error handling

4. **Testing**:
   - Created extensive unit tests for all new functionality
   - Implemented integration tests for end-to-end flows
   - Ensured all error paths are properly tested

5. **Documentation & Examples**:
   - Created comprehensive documentation for the delegation feature
   - Added well-commented example code
   - Documented best practices and comparison with AgentTool

The agent delegation feature now provides a robust mechanism for creating complex agent workflows with:
- Seamless session state sharing between agents
- LLM-driven delegation decisions
- Comprehensive error handling and validation
- Flexible agent discovery options (hierarchy or registry)

This implementation aligns with the original design goals and provides a powerful way to create sophisticated multi-agent systems in ADK-Ruby. 