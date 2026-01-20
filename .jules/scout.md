## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2025-05-20 - Reducing Agent Complexity

**Issue:** `ADK::Agent#execute_plan` and `execute_step` had very high ABC size and complexity scores, contributing significantly to `ADK::Agent` being a God Class.
**Learning:** Complex algorithmic logic (like plan execution with variable injection and error handling) should be encapsulated in its own class rather than being private methods of a large stateful object.
**Action:** Extracted `ADK::PlanExecutor` to house this logic, reducing `ADK::Agent` size and complexity.
