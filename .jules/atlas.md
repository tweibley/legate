## 2024-12-26 - Extracted MCP Connection Logic

**Issue:** `ADK::Agent` (800+ lines) was acting as a God Class, directly managing low-level MCP connection lifecycles, tool discovery, and error handling, in addition to its core responsibilities of planning and execution.

**Learning:** This coupling made it impossible to test MCP logic in isolation and violated the Single Responsibility Principle. Infrastructure concerns (connections) were mixed with domain concerns (agent behavior).

**Action:** Extracted `ADK::Mcp::ConnectionManager` to handle:
1. Connecting to multiple MCP servers.
2. Managing the lifecycle of `ADK::Mcp::Client` instances.
3. Registering discovered tools into a registry.
This reduces `ADK::Agent` complexity and allows the connection logic to be reused or tested independently.
