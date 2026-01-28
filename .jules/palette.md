## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-23 - [Did You Mean Suggestions]

**Learning:** CLI commands like `save` and `execute` benefit greatly from typo correction. Ruby's built-in `did_you_mean` gem is available and easy to integrate.
**Action:** Always use `DidYouMean::SpellChecker` when validating user input against a known list of valid options (tools, parameters, etc.) to provide actionable feedback.
