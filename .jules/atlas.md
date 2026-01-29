## 2025-12-18 - Separation of Definition and Runtime

**Issue:** `ADK::Agent` class in `lib/adk/agent.rb` contained both the runtime agent logic and the `AgentDefinition` class (plus its DSL), resulting in a file over 1000 lines long and mixed concerns.
**Learning:** Keeping static configuration (definition) tightly coupled with runtime behavior makes the code harder to navigate and test in isolation.
**Action:** Extracted `ADK::AgentDefinition` into a dedicated file `lib/adk/agent_definition.rb`. This separates the "blueprint" from the "machine", following the Single Responsibility Principle.

## 2025-12-17 - Extract Tool Loading Logic

**Issue:** `ADK::Agent` contained private logic (`_discover_and_load_tools`) to traverse the filesystem and require ruby files for tool discovery. This coupled the Agent's core domain logic (planning, execution) with infrastructure concerns (file I/O, loading).

**Learning:** Separating infrastructure concerns from domain logic improves testability and clarity. The Agent should not care *how* tools are loaded, only that they are available. By moving this logic to a dedicated `ADK::ToolLoader`, we create a reusable component that could be used by other parts of the system (e.g., CLI) and simplify the Agent class.

**Action:** Created `lib/adk/tool_loader.rb` to encapsulate file traversal and loading. Refactored `ADK::Agent` to delegate to this new module. This maintains the same behavior but enforces better module boundaries.

## 2025-01-01 - Global State vs Registry Instance

**Issue:** `ADK::GlobalToolManager` was implemented as a module with global state (`@@defined_tools`), creating a hard dependency and making it difficult to test without explicit reset logic. It duplicated the functionality of `ADK::ToolRegistry` which is instance-based.
**Learning:** Singleton patterns implemented via module variables often lead to hidden state and duplication when "instance" versions of the same concept (Registry) are introduced later. Delegating to a singleton instance of the Registry class unifies the logic.
**Action:** Refactored `GlobalToolManager` to delegate to a singleton instance of `ToolRegistry`, unifying the implementation while preserving the legacy static API.
