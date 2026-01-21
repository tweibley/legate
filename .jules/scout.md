## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2025-05-20 - Dead Code Retention

**Issue:** Deprecated method `parse_gemini_response` remained in `ADK::Planner` despite being fully replaced by `validate_and_format_multi_step_plan` and unused in production.
**Learning:** Leaving deprecated code "just in case" adds noise and confusion to complex classes like `Planner`.
**Action:** Aggressively prune deprecated methods once replacement logic is verified and stable.
