## 2025-12-18 - Separation of Definition and Runtime

**Issue:** `ADK::Agent` class in `lib/adk/agent.rb` contained both the runtime agent logic and the `AgentDefinition` class (plus its DSL), resulting in a file over 1000 lines long and mixed concerns.
**Learning:** Keeping static configuration (definition) tightly coupled with runtime behavior makes the code harder to navigate and test in isolation.
**Action:** Extracted `ADK::AgentDefinition` into a dedicated file `lib/adk/agent_definition.rb`. This separates the "blueprint" from the "machine", following the Single Responsibility Principle.

## 2025-12-17 - Extract Tool Loading Logic

**Issue:** `ADK::Agent` contained private logic (`_discover_and_load_tools`) to traverse the filesystem and require ruby files for tool discovery. This coupled the Agent's core domain logic (planning, execution) with infrastructure concerns (file I/O, loading).

**Learning:** Separating infrastructure concerns from domain logic improves testability and clarity. The Agent should not care *how* tools are loaded, only that they are available. By moving this logic to a dedicated `ADK::ToolLoader`, we create a reusable component that could be used by other parts of the system (e.g., CLI) and simplify the Agent class.

**Action:** Created `lib/adk/tool_loader.rb` to encapsulate file traversal and loading. Refactored `ADK::Agent` to delegate to this new module. This maintains the same behavior but enforces better module boundaries.

## 2025-05-23 - Extract MCP Connection Logic

**Issue:** `ADK::Agent` managed the lifecycle of MCP (Model Context Protocol) connections, including configuration parsing, connection establishment, and tool discovery. This contributed to the "God class" nature of `Agent` and coupled it to specific protocol implementations.
**Learning:** Protocol-specific lifecycle management (connect/disconnect/discovery) is an infrastructure concern distinct from the agent's core loop. Extracting this into a manager clarifies the agent's dependencies and simplifies its initialization.
**Action:** Extracted `ADK::Mcp::ConnectionManager` to handle all MCP-related operations. `ADK::Agent` now delegates these tasks, reducing its responsibility surface.
