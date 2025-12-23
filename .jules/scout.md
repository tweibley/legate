## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2025-02-18 - Missing Test Coverage for Core Logic

**Issue:** `ADK::Tool#coerce_value` contained complex logic for multiple types but lacked comprehensive unit tests. Existing tests mocked the coercion or only tested happy paths indirectly.
**Learning:** Core framework logic like parameter coercion often accumulates complexity over time. Refactoring it is risky without explicit, granular tests covering edge cases (e.g. malformed JSON strings for array/hash types).
**Action:** Created `spec/adk/tool_coercion_spec.rb` to cover all coercion types before refactoring. Always verify coverage of core "plumbing" methods before touching them.
