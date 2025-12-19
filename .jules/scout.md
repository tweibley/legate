## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2025-12-19 - Exception Scope in Refactoring

**Issue:** Extracting logic from a method (`perform_execution`) inadvertently moved it outside a `begin/rescue` block, changing the error handling behavior from wrapped `ToolError` to raw exceptions.
**Learning:** Refactoring for readability can silently break error handling contracts if the scope of `rescue` blocks is not preserved.
**Action:** When extracting methods, map the original exception handling boundaries to the new structure. If code moves, its safety net must move with it.
