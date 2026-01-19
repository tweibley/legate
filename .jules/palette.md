## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-24 - DidYouMean Suggestions

**Learning:** Users frequently make typos in CLI arguments (like tool names or parameters). Generic "unknown parameter" errors are frustrating and require consulting documentation. Ruby's built-in `did_you_mean` gem provides an easy way to offer helpful suggestions without adding dependencies.
**Action:** When validating user input against a known set of options (keys, command names), instantiate `DidYouMean::SpellChecker` with the valid keys and append `Did you mean '#{suggestion}'?` to the error/warning message.
