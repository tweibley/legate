## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2025-05-24 - Refactoring Plan Execution

**Issue:** `ADK::Agent#execute_plan` had high ABC Size and Method Length due to inline logic for parameter injection and result sanitization.
**Learning:** Core execution loops often accumulate complexity as new features (like MAS, injection, sanitization) are added inline.
**Action:** Extract distinct responsibilities (parameter injection, result sanitization) into dedicated private helper methods to keep the main execution flow clean.
