## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2025-05-15 - Refactoring ADK::Agent#execute_plan

**Issue:** `ADK::Agent#execute_plan` contained deep nesting and complex inline parameter injection logic, leading to high ABC size and poor readability.
**Learning:** Core execution loops often accumulate business logic for edge cases (like parameter injection from different result keys) which should be delegated to private helpers.
**Action:** Extracted `_resolve_step_params` and its helpers `_resolve_single_param` and `_extract_injection_value` to isolate the injection strategy from the execution flow.
