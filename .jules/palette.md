## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2025-05-18 - [CLI Progress Indicators]

**Learning:** When adding `CLI::UI::Spinner` to existing Thor commands, be mindful of test expectations. `Thor::Shell::Basic` mocks often capture `say` output, but `CLI::UI` writes directly to stdout/stderr.
**Action:** When introducing `CLI::UI` components, ensure tests either mock the UI component or adjust expectations to account for the UI handling the output instead of standard Thor messages. Also ensure `quiet` mode bypasses the UI component to preserve scriptability.
