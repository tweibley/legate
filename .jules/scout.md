## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2025-10-26 - Parameter Injection Logic Refactoring

**Issue:** `ADK::Agent#execute_plan` was overloaded with complex parameter injection logic using string placeholders (e.g., `[Result from step ...]`).
**Learning:** String-based parameter placeholders create a "stringly typed" dependency that is hard to test and maintain when mixed with control flow logic.
**Action:** Extracted the injection logic into `inject_previous_result` and helper methods to isolate this pattern and make `execute_plan` cleaner.
