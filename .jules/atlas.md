## 2025-12-18 - Separation of Definition and Runtime

**Issue:** `ADK::Agent` class in `lib/adk/agent.rb` contained both the runtime agent logic and the `AgentDefinition` class (plus its DSL), resulting in a file over 1000 lines long and mixed concerns.
**Learning:** Keeping static configuration (definition) tightly coupled with runtime behavior makes the code harder to navigate and test in isolation.
**Action:** Extracted `ADK::AgentDefinition` into a dedicated file `lib/adk/agent_definition.rb`. This separates the "blueprint" from the "machine", following the Single Responsibility Principle.

## 2025-12-17 - Extract Tool Loading Logic

**Issue:** `ADK::Agent` contained private logic (`_discover_and_load_tools`) to traverse the filesystem and require ruby files for tool discovery. This coupled the Agent's core domain logic (planning, execution) with infrastructure concerns (file I/O, loading).

**Learning:** Separating infrastructure concerns from domain logic improves testability and clarity. The Agent should not care *how* tools are loaded, only that they are available. By moving this logic to a dedicated `ADK::ToolLoader`, we create a reusable component that could be used by other parts of the system (e.g., CLI) and simplify the Agent class.

**Action:** Created `lib/adk/tool_loader.rb` to encapsulate file traversal and loading. Refactored `ADK::Agent` to delegate to this new module. This maintains the same behavior but enforces better module boundaries.

## 2025-05-20 - Extract Execution Logic

**Issue:** `ADK::Agent` was a God Class handling configuration, execution, MAS, and tools. The execution logic (`execute_plan`, `execute_step`) was complex and mixed with agent state management.
**Learning:** Core execution loops (iterating over steps, handling results, error handling) are distinct from the entity (Agent) that holds state and configuration. Separating them allows for better testing and potential future flexibility in execution strategies.
**Action:** Extracted `ADK::PlanExecutor` in `lib/adk/plan_executor.rb` to encapsulate the plan execution responsibility. `ADK::Agent` now delegates execution to this component.
