## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-24 - Helpful Typos Suggestions

**Learning:** Developers often typo parameter names (e.g., `locatoin` instead of `location`). The default error message "Missing required parameters: location" is technically correct but frustrating because the user *thought* they provided it.
**Action:** Enhanced `ADK::Tool#validate_and_coerce_params` to use `DidYouMean::SpellChecker`. Now, if a required parameter is missing, it checks provided keys for typos and suggests the intended parameter ("Did you mean 'location' instead of 'locatoin'?"). This turns a "check the docs" moment into an immediate fix.
