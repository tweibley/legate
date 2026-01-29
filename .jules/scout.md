## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2025-05-23 - Duplicated Redis Logic in MCP Adapter

**Issue:** `AdkAgentAdapter` manually implemented Redis loading logic that duplicated `ADK::AgentDefinitionStore`.
**Learning:** `AdkAgentAdapter` was likely written before the store was fully established or the author was unaware of it. The `AgentDefinition.from_hash` method is flexible enough to handle raw Redis data, so duplication was unnecessary.
**Action:** Always check for existing service/store classes before implementing raw data access logic.
