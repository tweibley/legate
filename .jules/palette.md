## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-22 - Did You Mean Suggestions

**Learning:** `DidYouMean::SpellChecker` (stdlib) is an easy win for CLI typos, but requires fetching the "dictionary" (valid names) first. In ADK, fetching just names from Redis (`smembers`) is much faster/safer than loading full definitions (`load_all_from_redis`) just for a suggestion.
**Action:** When implementing suggestions, always look for a lightweight "list names" query instead of loading full objects.
