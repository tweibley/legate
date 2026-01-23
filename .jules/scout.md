## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2026-01-23 - Partial Refactoring ADK::Agent#initialize

**Issue:** `ADK::Agent#initialize` was a massive 165-line method.
**Learning:** Big-bang refactors can be risky and violate size constraints. Iterative extraction is preferred.
**Action:** Extracted `initialize_sub_agents` into a private method, reducing `initialize` by ~50 lines. This isolates the complex sub-agent instantiation logic.
