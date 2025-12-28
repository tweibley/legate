## 2025-12-18 - Separation of Definition and Runtime

**Issue:** `ADK::Agent` class in `lib/adk/agent.rb` contained both the runtime agent logic and the `AgentDefinition` class (plus its DSL), resulting in a file over 1000 lines long and mixed concerns.
**Learning:** Keeping static configuration (definition) tightly coupled with runtime behavior makes the code harder to navigate and test in isolation.
**Action:** Extracted `ADK::AgentDefinition` into a dedicated file `lib/adk/agent_definition.rb`. This separates the "blueprint" from the "machine", following the Single Responsibility Principle.

## 2025-12-17 - Extract Tool Loading Logic

**Issue:** `ADK::Agent` contained private logic (`_discover_and_load_tools`) to traverse the filesystem and require ruby files for tool discovery. This coupled the Agent's core domain logic (planning, execution) with infrastructure concerns (file I/O, loading).

**Learning:** Separating infrastructure concerns from domain logic improves testability and clarity. The Agent should not care *how* tools are loaded, only that they are available. By moving this logic to a dedicated `ADK::ToolLoader`, we create a reusable component that could be used by other parts of the system (e.g., CLI) and simplify the Agent class.

**Action:** Created `lib/adk/tool_loader.rb` to encapsulate file traversal and loading. Refactored `ADK::Agent` to delegate to this new module. This maintains the same behavior but enforces better module boundaries.

## 2025-12-28 - Extracted MCP Connection Management

**Issue:** `ADK::Agent` was directly responsible for MCP (Model Context Protocol) connection lifecycle, including client initialization, handshake, and tool discovery loops. This violated the Single Responsibility Principle and tightly coupled the agent core to MCP implementation details.

**Learning:** MCP connection logic involves specific steps (handshake, capabilities negotiation, schema translation) that are distinct from the agent's core task execution loop. Keeping them in the agent makes the agent class bloated and hard to test in isolation from network concerns.

**Action:** Extracted `ADK::Mcp::ConnectionManager` to handle all MCP connection and tool discovery logic. The Agent now delegates to this manager, reducing its own complexity and decoupling it from the specifics of the MCP protocol.
