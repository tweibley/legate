## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-24 - Structured CLI Output for Agent Lists

**Learning:** Human-readable CLI output (like `adk agent list`) is often parsed by scripts, creating a tension between UX (formatting/frames) and scriptability.
**Action:** When improving CLI output with libraries like `CLI::UI`, ensure a robust `--json` flag exists and is well-documented as the stable interface for scripts. This allows us to make the default output rich and user-friendly without breaking automation that opts into JSON.
