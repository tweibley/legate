## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-24 - Helpful Parameter Typo Suggestions

**Learning:** Since `ADK::Tool` gracefully ignores extra parameters, traditional "unknown argument" errors are impossible to trigger. However, missing required parameters often stem from typos (e.g., `:locatoin` vs `:location`).
**Action:** Enhanced `validate_and_coerce_params` to use `DidYouMean` (if available) to scan provided parameters for similarities to *missing required* parameters, offering specific "Did you mean?" suggestions in the error message.
