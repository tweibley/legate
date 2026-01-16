## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2025-02-23 - Suggesting Corrections in CLI

**Learning:** Developers often typo tool names in `agent save` or parameter keys in `tool execute`, leading to "ignoring" warnings that are easy to miss or confusing.
**Action:** Integrated `DidYouMean::SpellChecker` in CLI commands to:
1. Detect unknown tool names and suggest the closest match from registered tools.
2. Detect unknown parameter keys and suggest the closest match from tool definition.
This turns a generic "ignoring" warning into an actionable "Did you mean X?" prompt, reducing friction.
