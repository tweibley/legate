## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-01-27 - Helping Hand for CLI Typos

**Learning:** When users mistype a resource name (like an agent), a generic "Not Found" error is a dead end. Providing a "Did you mean?" suggestion transforms a frustration into a quick recovery.
**Action:** Always check if a lookup failure might be a typo by comparing against known valid keys, especially in CLI interfaces where exact spelling is required.
