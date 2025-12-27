## 2024-05-24 - Extract MCP ConnectionManager

**Issue:** `ADK::Agent` was acting as a "God Class" with too many responsibilities, including managing MCP connections, tool discovery, and client lifecycle. This high coupling made it difficult to test connection logic in isolation and bloated the agent class.

**Learning:** Extracting connection management into a dedicated `ADK::Mcp::ConnectionManager` improves cohesion. By passing only the necessary dependencies (`tool_registry` and `allowed_tool_names`) instead of the entire `Agent` instance, we reduce coupling and make the new class easier to test and reuse.

**Action:** Created `ADK::Mcp::ConnectionManager` to encapsulate all MCP connection logic. Refactored `ADK::Agent` to delegate these responsibilities to the new manager. This pattern of extracting specific responsibilities into helper classes should be applied to other parts of `ADK::Agent` (e.g., MAS delegation, execution logic) in future refactorings.
