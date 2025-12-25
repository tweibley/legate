## 2024-05-24 - Extracting Infrastructure from Core Domain

**Issue:** `ADK::Agent` was acting as a "God class", handling not only core agent logic but also low-level MCP infrastructure concerns like parsing configs, creating clients, and managing connection lifecycles. This made `Agent` harder to test and violated SRP.

**Learning:** "Infrastructure / Adapters" (like MCP connections) should be separated from "Domain Models" (`ADK::Agent`). The `Agent` should depend on an abstraction or a dedicated manager for these external connections, rather than implementing the connection logic internally.

**Action:** Extracted `ADK::Mcp::ConnectionManager` to encapsulate all MCP connection logic. `ADK::Agent` now delegates to this manager. This reduced the size and complexity of `ADK::Agent` and made MCP connection logic independently testable.
