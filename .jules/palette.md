## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-24 - CLI Typo Suggestions

**Learning:** When using CLI tools with many named entities (like agents), typos are frequent. Simply stating "not found" is frustrating and halts flow. `DidYouMean` is a powerful, low-effort way to guide users back to the happy path immediately.
**Action:** Always check if a lookup failure involves a named entity that belongs to a known set. If so, use `DidYouMean::SpellChecker` to suggest the intended target in the error message.
