## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-22 - DidYouMean for Custom CLI Inputs

**Learning:** Ruby's `did_you_mean` gem (bundled) provides a `SpellChecker` class that can be easily used for custom suggestions against any list of strings, not just method names.
**Action:** Use `DidYouMean::SpellChecker.new(dictionary: list).correct(input).first` to improve CLI error messages when a user input matches nothing but is close to a valid option.
