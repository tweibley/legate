## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-24 - CLI Verbosity Control

**Learning:** Relying solely on environment variables (`ADK_LOG_LEVEL`) for logging verbosity in CLI tools leads to poor UX. In development, the default `DEBUG` level drowned out command output. Users expect standard output by default and debug logs only when requesting `--verbose`.
**Action:** Added centralized `--verbose` flag handling in `OutputHelper` and applied it to key CLI commands (`agent start`, `execute`, `chat`, `tool execute`). This puts control in the user's hands.
