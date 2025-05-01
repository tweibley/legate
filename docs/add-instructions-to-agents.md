# Plan: Adding Agent Instructions to ADK Ruby

This document outlines the steps required to add an `instruction` feature to ADK Ruby agents, allowing for better guidance of their behavior, similar to system prompts in LLMs.

## 1. Define `instruction` Property (Refined)

*   **Goal:** Add an `instruction` string attribute to the `Agent`.
*   **Implementation:**
    *   Modify `ADK::Agent::AgentBuilder`: Add `attr_accessor :instruction`.
    *   Modify `ADK::Agent#initialize`:
        *   Add `instruction: nil` to the parameter list.
        *   Store the value: `@instruction = instruction`.
    *   Modify `ADK::Agent`: Add `attr_reader :instruction`.
    *   Update `ADK::Agent::AgentBuilder#build` to pass the collected `@instruction` to `ADK::Agent.new`.
    *   The primary way to set it will be via the `Agent.define` DSL:
        ```ruby
        ADK::Agent.define do |a|
          a.name = 'example_agent'
          a.description = '...'
          a.instruction = "You are a helpful assistant that only uses the tools provided. Respond concisely." # New line
          # ... other config
        end
        ```
*   **Content:** The string should contain the agent's core goal, persona, behavioral constraints, tool usage guidelines, and desired output format.

## 2. Integrate Instructions into `Adk::Planner` (Refined)

*   **Goal:** Modify the planner to use the agent's instruction when generating prompts for the LLM.
*   **Implementation:**
    *   `Adk::Planner#initialize` already receives and stores the `agent` instance (`@agent`).
    *   Modify `Adk::Planner#build_multi_step_gemini_prompt`:
        *   Retrieve the instruction: `instruction = @agent.instruction`.
        *   Prepend the instruction to the prompt string if it's present and not empty.
    *   *Refined Prompt Structure:*
        ```
        # If instruction is present:
        [AGENT_INSTRUCTION: You are a helpful assistant...]
        ---
        # Existing prompt content follows:
        You are an AI planner...

        User Request: "[task]"
        Available Tools:
        ---
        [tools_description]
        ---
        Instructions:
        [planning_instructions]
        ```

## 3. Update Agent Execution Flow (Refined)

*   **Goal:** Ensure the `instruction` is available when the `Planner` needs it.
*   **Implementation:**
    *   This is largely handled by the changes in Step 1 & 2. Since `Planner` is initialized with the `Agent` instance in `Agent#initialize`, and `instruction` is added as an attribute to `Agent`, the planner will have access to it via `@agent.instruction` when `build_multi_step_gemini_prompt` is called. No specific changes needed in `SessionService` for passing the instruction.

## 4. Review MCP Adapters

*   **Goal:** Ensure MCP adapters handle the new instruction property correctly.
*   **Implementation:**
    *   If adapters reconstruct `Agent` objects or directly instantiate `Planner`, they would need to be updated to handle the new `instruction` parameter during initialization. Minimal changes anticipated otherwise.

## 5. Testing

*   **Goal:** Verify the feature works as intended.
*   **Implementation:**
    *   **Unit Tests (`spec/adk/agent_spec.rb`):**
        *   Verify `ADK::Agent.define` correctly assigns the `instruction`.
        *   Verify `ADK::Agent#initialize` correctly stores the `instruction` attribute.
        *   Verify agents defined without an instruction default to `nil` or empty.
    *   **Unit Tests (`spec/adk/planner_spec.rb`):**
        *   Mock `Agent` instances with and without instructions.
        *   Test `planner.send(:build_multi_step_gemini_prompt, ...)`.
        *   Assert the generated prompt correctly includes (or excludes) the instruction string and formatting based on the mock agent's state.
    *   **Integration/Feature Tests (e.g., `spec/adk/agent_integration_spec.rb`):**
        *   These tests will likely require mocking the LLM call (`Gemini::Client#generate_content`).
        *   **Constraint Test:** Define an agent with a constraint instruction (e.g., "Never use tool X"). Provide a task requiring tool X. Mock the LLM to receive the constraint and return an empty plan (`[]`). Assert the agent handles the empty plan correctly (e.g., returns a planning error or uses fallback).
        *   **Tool Guidance Test:** Define an agent with guidance (e.g., "Prefer tool A over tool B"). Provide a task solvable by both. Mock the LLM to receive the guidance and return a plan using only tool A. Assert the agent executes the plan with tool A.

## 6. Documentation & Examples

*   **Goal:** Document the feature and provide usage examples.
*   **Implementation:**
    *   Update `README.md` and other relevant documentation files.
    *   Explain how to define and use the `instruction` property via the `Agent.define` DSL.
    *   Add new examples in the `examples/` directory showcasing agents utilizing instructions for various purposes. 