## Plan for Implementing Multi-Agent Systems (MAS) in ADK-Ruby

This plan outlines the features and changes needed to support multi-agent systems in `adk-ruby`, inspired by the provided `adk-python` documentation. The core idea is to allow `ADK::Agent` instances to be composed into hierarchies and orchestrated by specialized workflow agents.

### Phase 1: Core Agent Hierarchy and State Management Enhancements

**Objective:** Establish the foundational parent-child agent relationships and improve inter-agent communication via shared state.

1.  **Modify `ADK::Agent` for Hierarchy:**
    *   **New Attributes:**
        *   `parent_agent`: A reader attribute to store a reference to the parent `ADK::Agent` instance. This should be a weak reference if possible, or managed carefully to avoid retain cycles if agents hold strong references to children.
        *   `sub_agents`: A reader attribute, an array storing instances of child `ADK::Agent`s.
    *   **Initialization (`ADK::Agent#initialize`):**
        *   Add an optional `sub_agents: []` keyword argument. This argument would take an array of already instantiated `ADK::Agent` objects.
        *   When `sub_agents` are provided to a parent during its initialization:
            *   Iterate through each `sub_agent` instance.
            *   **Single Parent Rule:** Before assigning, check if `sub_agent.parent_agent` is already set. If so, raise a `ValueError` (or a new `ADK::HierarchyError`).
            *   Set `sub_agent.instance_variable_set(:@parent_agent, self)` (the parent agent instance).
            *   Store the validated `sub_agents` array in the parent's `@sub_agents` instance variable.
    *   **Navigation Method:**
        *   Implement `ADK::Agent#find_sub_agent(name_sym)`:
            *   Searches its `@sub_agents` list for an agent whose `name` attribute matches `name_sym`.
            *   Consider a recursive version `find_descendant_agent(name_sym)` later if deep searching is needed.
    *   **`ADK::AgentDefinition` Considerations:**
        *   Currently, definitions are loaded from a store and don't directly reference other *instances*. For defining hierarchies via definitions:
            *   A `sub_agent_definitions: []` attribute could be added to `ADK::AgentDefinition`, storing an array of *names* (symbols) of other agent definitions.
            *   When a parent agent is instantiated from such a definition, its `initialize` or `start` method would be responsible for:
                1.  Loading the definitions of its named sub-agents from the `DefinitionStore`.
                2.  Instantiating these sub-agents.
                3.  Establishing the parent-child links as described above.
            *   This keeps definitions serializable. The actual agent object graph is built at runtime.

2.  **Enhance State Management for Inter-Agent Communication:**
    *   **`output_key` for `ADK::Agent`:**
        *   Add an optional `output_key: nil` (String or Symbol) attribute to `ADK::Agent` class and to the `ADK::AgentDefinition` DSL (`a.output_key :my_data_key`).
        *   Modify `ADK::Agent#run_task`:
            *   After successfully executing its plan and generating a final result (from the agent event's content), if `output_key` is set and the result is not an error, the agent should use the `session_service` to save this result to the current session's state.
            *   E.g., `session_service.set_session_state(session_id, output_key, final_result_content)`. This implies `SessionService` might need a `set_session_state` method or `ADK::Session` would handle `set_state` and the service would persist the whole session. Given `ADK::Session` already has state management, the agent would call `session.set_state(output_key, final_result_content)` and the `SessionService` would persist the updated session.
    *   **Shared Session Context:** Emphasize in documentation that sub-agents run by workflow agents will typically operate within the *same session ID* and use the *same `SessionService` instance* as their parent workflow agent. This is the primary mechanism for state sharing.

### Phase 2: Workflow Agent Implementation

**Objective:** Create new agent classes inheriting from `ADK::Agent` that specialize in orchestrating their `sub_agents`.

*   **Base `ADK::WorkflowAgent < ADK::Agent` (Conceptual Abstract Class):**
    *   Could hold common logic for managing `sub_agent_definitions` (list of names/configs for children) and instantiating them.
    *   Its `initialize` would likely take `sub_agent_definitions:` instead of direct `sub_agents:` instances, then load/instantiate them.

1.  **`ADK::Agents::SequentialAgent < ADK::Agent` (or `ADK::WorkflowAgent`):**
    *   **Definition (`ADK::Agent.define` block):**
        *   `a.sub_agent_sequence [:agent_one_name, :agent_two_name, {name: :agent_three_name, input_mapping: {...}}]`
        *   This defines the names and order of sub-agents. `input_mapping` could specify how to form the input for a sub-agent (e.g., from previous step's `output_key` or original input).
    *   **Instantiation:** When a `SequentialAgent` is created, it loads/instantiates its sub-agents based on `sub_agent_sequence`.
    *   **`run_task` Logic:**
        *   Iterates through its ordered sub-agents.
        *   For each `sub_agent`:
            *   Retrieves the current session using `session_id` and `session_service`.
            *   Determines the `user_input` for the sub-agent based on its configuration (original task input, output from previous step via state, or a static value).
            *   Calls `sub_agent.run_task(...)` with the same `session_id` and `session_service`.
            *   If a sub-agent returns an error status or an "escalate" signal, the `SequentialAgent` may terminate and propagate the result.
            *   The `output_key` feature (from Phase 1) is crucial here.
    *   **Result:** The result of the `SequentialAgent` could be the result of its last sub-agent, or a specifically designated aggregation.

2.  **`ADK::Agents::ParallelAgent < ADK::Agent`:**
    *   **Definition:**
        *   `a.parallel_sub_agents [:fetch_weather_agent, :fetch_news_agent]`
    *   **Instantiation:** Loads/instantiates sub-agents.
    *   **`run_task` Logic:**
        *   For each `sub_agent`, launch `sub_agent.run_task(...)` in a separate thread (e.g., using `Concurrent::Future` or `Thread.new`).
        *   All sub-agents use the same `session_id` and `session_service`.
        *   **State Management:** Sub-agents should write their results to *distinct* keys in the session state (e.g., `weather_agent` uses `output_key :weather_data`).
        *   The `ParallelAgent` waits for all child tasks to complete.
        *   **Result:** Could return a status indicating completion, or a hash of job IDs if sub-agents are async, or simply rely on state being populated. The Python version mentions context branching, which is complex. For Ruby V1, shared state with distinct keys is simpler.
    *   **Concurrency:** Use `concurrent-ruby` gem for robust parallel execution.

3.  **`ADK::Agents::LoopAgent < ADK::Agent`:**
    *   **Definition:**
        *   `a.loop_sub_agents [:process_item_agent, :check_condition_agent]`
        *   `a.loop_max_iterations 10`
        *   `a.loop_condition_state_key :is_loop_done` (optional, for state-based termination)
    *   **Instantiation:** Loads/instantiates sub-agents.
    *   **`run_task` Logic:**
        *   Loops up to `max_iterations`.
        *   In each iteration, executes `loop_sub_agents` sequentially (like `SequentialAgent`).
        *   **Termination:**
            *   `max_iterations` reached.
            *   A sub-agent's returned event has `actions.escalate == true` (requires adding `actions` to `ADK::Event`).
            *   (Optional) If `loop_condition_state_key` is set, check its value in session state after each full iteration.
        *   Shared session state is crucial for loop-carried dependencies and termination conditions.

4.  **Event Escalation (`ADK::Event` modification):**
    *   Add an optional `actions: nil` hash attribute to `ADK::Event`.
    *   Example: `ADK::Event.new(..., actions: { escalate: true, reason: "Condition met" })`.
    *   Workflow agents will inspect this field.

### Phase 3: Advanced Interaction Mechanisms

**Objective:** Implement dynamic LLM-driven delegation and ensure explicit agent-as-tool invocation aligns with MAS principles.

1.  **LLM-Driven Delegation (Control Flow Transfer):**
    *   **Mechanism:** This is distinct from `ADK::Tools::AgentTool`. It's about the LLM deciding to change the "active" agent for the current overall task.
    *   **Planner Output:** The `ADK::Planner` (or the LLM it uses) must be able to output a special plan step indicating a transfer.
        *   Example plan step: `{ type: :agent_transfer, target_agent_name: :billing_agent, new_task_input: "User wants to update payment method." }`
    *   **`ADK::Agent#execute_plan` Modification:**
        *   When this step type is encountered:
            1.  The current (parent) agent uses `self.find_sub_agent(target_agent_name)` to get the instance of the sub-agent. (This assumes the target is a direct sub-agent. For arbitrary hierarchy, it might use `self.find_descendant_agent` or even search upwards via `parent_agent` and then down other branches, which is more complex). *V1: Target must be a configured sub-agent of the delegating agent.*
            2.  If found, the parent agent calls `target_sub_agent.run_task(...)` with the `new_task_input`, and crucially, the *same `session_id` and `session_service`*.
            3.  The result from `target_sub_agent.run_task` becomes the result of this "transfer" step in the parent's plan execution. The parent then continues its own plan or concludes.
    *   **Configuration:**
        *   An agent definition might have `a.can_delegate_to [:sub_agent1, :sub_agent2]` to inform its LLM about potential targets.
        *   The agent's main `instruction` prompt needs to guide the LLM on when and how to choose delegation.

2.  **Review and Enhance `ADK::Tools::AgentTool` (Explicit Invocation):**
    *   **Current Behavior:** `ADK::Tools::AgentTool` in Ruby instantiates the target agent from its definition stored in `DefinitionStore` and runs it in a *new, temporary session*.
    *   **Alignment with Python's `AgentTool(agent=instance)`:**
        *   **Option 1 (Closer Alignment):** Modify `ADK::Tools::AgentTool` to optionally accept an already-instantiated `ADK::Agent` object during its own initialization (`ADK::Tools::AgentTool.new(target_agent_instance: my_agent_obj)`).
            *   If an instance is provided, `perform_execution` would call `target_agent_instance.run_task(...)`.
            *   **Crucial:** This `run_task` call should use the *calling agent's* `session_id` and `session_service` (from the `ToolContext`) to enable shared state if desired. This differs from its current isolated session behavior.
        *   **Option 2 (Alternative for Definition-Based):** Enhance the existing `AgentTool` so that when it instantiates an agent from a definition, it *can optionally be configured to run it within the calling agent's session context*. This might be a parameter to the `AgentTool` itself or its execution.
    *   **State Passing:** The Python example shows the target `ImageGeneratorAgent` reading `ctx.session.state.get("image_prompt")`. This implies the `AgentTool` ensures the target runs in a context where this state is accessible.
    *   **Return Value:** Ensure `AgentTool` correctly returns the `result` from the target agent's successful execution as its own `result`.
    *   **V1 Focus:** Prioritize Option 2 or ensure the current definition-based `AgentTool` can be made to use the caller's session when invoked. This is simpler than managing lifecycles of pre-instantiated agents passed to tools.

### Phase 4: Documentation, Examples, and Testing

1.  **Documentation:**
    *   Create new markdown files under `public/docs/multi_agent_systems/` covering:
        *   MAS Overview & Benefits in ADK-Ruby.
        *   Defining Agent Hierarchies (`parent_agent`, `sub_agents`, instantiation from definitions).
        *   Using Workflow Agents (`SequentialAgent`, `ParallelAgent`, `LoopAgent`) with configuration examples.
        *   Communication Patterns (Shared Session State via `output_key`, LLM-Driven Delegation, `AgentTool`).
        *   Event Escalation.
    *   Update existing architecture diagrams and agent lifecycle documents.
2.  **Examples:**
    *   Create new Ruby scripts in `examples/mas/` for each pattern:
        *   `coordinator_dispatcher_example.rb`
        *   `sequential_pipeline_example.rb`
        *   `parallel_fanout_example.rb`
        *   `loop_refinement_example.rb`
        *   `hierarchical_decomposition_example.rb` (might use LLM delegation or nested AgentTools)
3.  **Testing:**
    *   Add extensive RSpec tests for:
        *   Agent hierarchy setup and `find_sub_agent`.
        *   `output_key` functionality.
        *   Each workflow agent (`SequentialAgent`, `ParallelAgent`, `LoopAgent`), covering successful execution, error handling, and termination conditions.
        *   LLM-Driven Delegation mechanism (mocking planner output).
        *   Enhancements to `ADK::Tools::AgentTool`.

### Implementation Considerations:

*   **Agent Lifecycle in Workflows:** When a Workflow Agent runs its sub-agents, are these sub-agents instantiated fresh each time, or are they persistent children?
    *   *Proposal:* For sub-agents defined by *name* in a workflow agent's definition, they should be instantiated by the workflow agent when its own `run_task` is called, and potentially `start`ed and `stop`ped by the workflow agent during that run. This keeps them relatively stateless from the workflow's perspective, relying on shared session state.
*   **Error Handling in Workflow Agents:** Define clear strategies. If a sub-agent in a `SequentialAgent` fails, does the whole sequence stop? Can `ParallelAgent` collect partial results if some children fail?
*   **Clarity of `ADK::ToolContext` vs. Shared Session:** Re-emphasize that `ADK::ToolContext` is ephemeral for a single tool execution, while the `ADK::Session` (and its state, managed by `SessionService`) is the persistent carrier of information across multiple agent turns or sub-agent executions within the same overarching task.
*   **Defining Workflow Agents:** Use the existing `ADK::Agent.define` DSL. Add specific DSL methods for workflow configurations (e.g., `a.sequential_steps [...]`, `a.parallel_tasks [...]`, `a.loop_iterations X`).

This plan provides a phased approach. Phase 1 is foundational. Phase 2 introduces the core workflow mechanics. Phase 3 adds more sophisticated dynamic interactions.