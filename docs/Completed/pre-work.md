# Phase 1 MAS Implementation: Troubleshooting and Refinement Plan

This document outlines the key tasks to ensure a stable and correct implementation of Phase 1 (Core Agent Hierarchy and State Management) for the Multi-Agent System (MAS) in `adk-ruby`.

## 1. Refine and Simplify `ADK::Agent#initialize`

*   **Status:** Mostly Complete
*   **Description:** The `ADK::Agent#initialize` method is a critical point for agent creation and hierarchy setup. Its complexity needs to be managed carefully.
*   **Tasks:**
    *   [X] **Strictly Use `ADK::AgentDefinition` Objects:**
        *   Modified `ADK::Agent#initialize` to *only* accept fully formed `ADK::AgentDefinition` objects for its `definition:` parameter.
        *   Moved the responsibility of fetching raw definition hashes and converting them (using `ADK::AgentDefinition.from_hash`) to the code *calling* `ADK::Agent.new`.
        *   **Affected Files Refactored:**
            *   `lib/adk/agent.rb` (ADK::Agent#initialize modified)
            *   `lib/adk/tools/agent_tool.rb`
            *   `lib/adk/cli/agent_commands.rb`
            *   `lib/adk/mcp/server/adk_agent_adapter.rb`
            *   `lib/adk/cli/deployment_commands.rb` (sample entrypoint generator)
            *   `spec/adk/agent_spec.rb` (tests updated)
    *   [X] **Clear Logic for Sub-Agent Instantiation from Definition:** (This is part of the core MAS hierarchy not yet fully addressed by the `initialize` refactor alone)
        *   When an `ADK::Agent` is initialized with an `ADK::AgentDefinition` object:
            1.  Iterate over `definition.sub_agent_names`.
            2.  For each name, fetch the sub-agent's full `ADK::AgentDefinition` object (e.g., via `ADK::GlobalDefinitionRegistry` or `ADK::AgentDefinition.from_hash(store.get_definition(...))`).
            3.  Instantiate the sub-agent: `sub_agent = ADK::Agent.new(definition: sub_definition_object, session_service: self.session_service)`. Ensure `self.session_service` is correctly passed.
            4.  Set the parent link: `sub_agent.instance_variable_set(:@parent_agent, self)` (after robustly checking the single parent rule).
            5.  Add the new sub-agent to `self.sub_agents`.
    *   [X] **Clarify Programmatic vs. Declarative Sub-Agents:** (Also part of core MAS hierarchy)
        *   Define and implement clear rules if `ADK::Agent#initialize` can receive *both* sub-agents via the `definition.sub_agent_names` (declarative) and via a direct `sub_agents: [array_of_instances]` parameter (programmatic). Specify precedence or merging logic.

## 2. Verify `ADK::AgentDefinition.from_hash` and `ADK::AgentDefinition#to_h`

*   **Status:** Partially Complete
*   **Description:** These methods are crucial for the correct serialization and deserialization of agent definitions, especially with the new attributes for hierarchy (`sub_agent_names`) and state (`output_key`). Errors here can lead to incorrect agent behavior when definitions are loaded from persistence.
*   **Tasks:**
    *   [X] **Implement `ADK::AgentDefinition.from_hash`:**
        *   Added `ADK::AgentDefinition.from_hash` to `lib/adk/agent.rb` to handle deserialization for currently existing attributes.
        *   **TODO:** Update `from_hash` and `to_h` as new MAS-specific attributes (e.g., `sub_agents_define`, `output_key`, etc.) are added to `ADK::AgentDefinition`.
    *   [X] **Create Dedicated Unit Tests:**
        *   Write unit tests specifically for `ADK::AgentDefinition.from_hash` and `ADK::AgentDefinition#to_h`.
        *   **Test Flow:**
            1.  Programmatically create an `ADK::AgentDefinition` object using `DefinitionProxy`, setting all relevant attributes including future MAS attributes (`sub_agents_define`, `output_key`, etc.).
            2.  Convert this object to a hash using `to_h`.
            3.  Reconstruct an `ADK::AgentDefinition` object from this hash using `from_hash`.
            4.  Assert that the reconstructed object is identical to the original in all its attributes, paying special attention to data types (e.g., Symbols vs. Strings for names and keys).
    *   [X] **Verify Type Conversions for MAS Attributes:** Double-check that future MAS attributes (`sub_agent_names`, `output_key`) are consistently handled (e.g., stored as strings in hashes/JSON, but used as symbols within the `AgentDefinition` object).

## 3. Implement a Rigorous and Incremental Testing Strategy

*   **Status:** In Progress
*   **Description:** A layered testing approach will help isolate issues more effectively than end-to-end tests alone.
*   **Tasks:**
    *   [P] **Refactor Existing Specs:**
        *   `spec/adk/agent_spec.rb` has been significantly refactored to align with the new `ADK::Agent#initialize(definition: ...)` signature.
    *   [X] **Test Programmatic Hierarchy Construction:** (Depends on MAS hierarchy attributes)
        *   Write tests that create parent and child agents *without* using `ADK::AgentDefinition` or the `RedisStore`.
        *   Directly call `ADK::Agent.new(definition: ..., sub_agents: [child_agent_instance])`. (Requires `sub_agents` param handling in `initialize`)
        *   Verify `parent_agent`, `sub_agents` attributes are correctly set.
        *   Test all hierarchy navigation methods (`find_sub_agent`, `root_agent`, `find_agent`).
        *   Specifically test the enforcement of the single parent rule in this context.
    *   [X] **Test Declarative Hierarchy (Definition-Driven, No Persistence):** (Depends on MAS hierarchy attributes in definition)
        *   Define agent structures (e.g., ParentA with `sub_agents_define :ChildB`, and ChildB) using the DSL.
        *   Manually create the corresponding `ADK::AgentDefinition` objects in your test setup.
        *   Instantiate the parent agent: `parent_instance = ADK::Agent.new(definition: parent_definition_obj, session_service: mock_session_service)`.
        *   Verify that `parent_instance.sub_agents` is correctly populated with an instance of ChildB, and that parent-child links are correctly established. This tests the sub-agent instantiation logic based on the definition object itself.
    *   [X] **Test Full Flow with Persistence:** (Depends on MAS hierarchy attributes in definition & store)
        *   Save agent definitions (e.g., ParentA, ChildB with MAS attrs) to the `RedisStore`.
        *   Load ParentA's definition *hash* from the store.
        *   Convert this hash to an `ADK::AgentDefinition` *object* using `ADK::AgentDefinition.from_hash`.
        *   Instantiate the parent agent: `parent_instance = ADK::Agent.new(definition: loaded_parent_definition_obj, ...)`.
        *   Verify the complete hierarchy, including sub-agent instantiation and parent-child links.
    *   [X] **Test State Management (`output_key`):** (Depends on `output_key` attribute in definition)
        *   Create focused tests for `ADK::Agent#run_task`.
        *   Use a mock `session_service`.
        *   Ensure that if an agent's definition includes an `output_key`, the `session_service.set_state(@output_key, result)` method is called with the correct parameters after `run_task` completes its primary execution.

## 4. Double-Check Key Implementation Details

*   **Status:** To Do
*   **Description:** Small oversights in critical areas can lead to widespread issues.
*   **Tasks:**
    *   [X] **Session Service Propagation for Sub-Agents:**
        *   Confirm that when a parent agent instantiates its sub-agents (from its definition), it correctly passes its own `@session_service` instance to the sub-agent's constructor.
    *   [X] **`ADK::GlobalDefinitionRegistry` (if used for MAS):**
        *   Ensure it consistently loads and returns fully populated `ADK::AgentDefinition` objects (including all MAS attributes).
        *   Verify its interaction with `ADK::AgentDefinition.from_hash` and the `RedisStore` is seamless and correct.
    *   [X] **Single Parent Rule Enforcement for MAS:**
        *   Rigorously check that the single parent rule is applied robustly when `@parent_agent` is set for sub-agents during MAS hierarchy construction.

## 5. Debugging Strategy

*   **Status:** Ongoing (as needed)
*   **Description:** When tests fail, a systematic approach to debugging is needed.
*   **Tasks:**
    *   [P] **Identify Specific Failing Specs:** Note down the exact test cases and assertion failures.
    *   [P] **Analyze Error Messages:** Carefully read the error messages and stack traces.
    *   [P] **Use Logging/Debuggers:** Add temporary logging or use a debugger to inspect variable states at critical points.

## 6. Next Steps: Refactor Remaining Callers & Update Documentation

*   **Status:** To Do
*   **Description:** Update remaining parts of the codebase and documentation to reflect the new `ADK::Agent.new(definition: ...)` pattern.
*   **Tasks:**
    *   [P] **Refactor Example Files:**
        *   Go through files in `examples/` directory (e.g., `simple_agent.rb`, `multi_tool_agent.rb`, etc.).
        *   For each, create an `ADK::AgentDefinition` programmatically (using `ADK::AgentDefinition.new.define { ... }`).
    *   [P] **Update Documentation Snippets:**
        *   Review and update code examples in all documentation files:
            *   `public/docs/`
            *   `docs/` (including `README.md`, `ideas/`, `Todo/` files that contain code snippets).
        *   Ensure all examples of `ADK::Agent.new` show the new definition-based initialization.
    *   [ ] **Address Other `grep` Results:** Systematically go through any remaining files flagged by the `grep ADK::Agent.new` search and refactor as needed. 