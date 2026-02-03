## 2025-12-18 - Separation of Definition and Runtime

**Issue:** `ADK::Agent` class in `lib/adk/agent.rb` contained both the runtime agent logic and the `AgentDefinition` class (plus its DSL), resulting in a file over 1000 lines long and mixed concerns.
**Learning:** Keeping static configuration (definition) tightly coupled with runtime behavior makes the code harder to navigate and test in isolation.
**Action:** Extracted `ADK::AgentDefinition` into a dedicated file `lib/adk/agent_definition.rb`. This separates the "blueprint" from the "machine", following the Single Responsibility Principle.

## 2025-12-17 - Extract Tool Loading Logic

**Issue:** `ADK::Agent` contained private logic (`_discover_and_load_tools`) to traverse the filesystem and require ruby files for tool discovery. This coupled the Agent's core domain logic (planning, execution) with infrastructure concerns (file I/O, loading).

**Learning:** Separating infrastructure concerns from domain logic improves testability and clarity. The Agent should not care *how* tools are loaded, only that they are available. By moving this logic to a dedicated `ADK::ToolLoader`, we create a reusable component that could be used by other parts of the system (e.g., CLI) and simplify the Agent class.

**Action:** Created `lib/adk/tool_loader.rb` to encapsulate file traversal and loading. Refactored `ADK::Agent` to delegate to this new module. This maintains the same behavior but enforces better module boundaries.


## 2026-02-03 - Error Handling Consolidation

**Issue:** Error definitions were scattered across `lib/adk/error.rb`, `lib/adk/errors.rb`, and `lib/adk/tool/error.rb`, with colliding class definitions (specifically `ADK::ToolError`) and inconsistent inheritance.
**Learning:** Ruby's open classes allow silent redefinition, which masked the collision between the basic `ToolError` in `errors.rb` and the richer implementation in `tool/error.rb`. Consolidating them into a single `lib/adk/errors.rb` prevents this ambiguity and simplifies the dependency graph.
**Action:** Centralized all ADK error classes into `lib/adk/errors.rb`, ensuring the richest definition (with `cause` and subclasses) was preserved, and removed the redundant files.
