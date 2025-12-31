## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-24 - DidYouMean Integration in Tools

**Learning:** Integrating `did_you_mean` into custom validation logic requires careful filtering of candidate keys. Initially, I compared all provided keys against missing required parameters. This resulted in valid, optional parameters (e.g., `operand1`) being suggested as typos for missing required ones (e.g., `operation`).
**Action:** When implementing "Did you mean?" logic for parameter validation, always calculate `unknown_keys = provided_keys - known_parameter_definitions` first, and only check those unknown keys for typos. This avoids confusing suggestions where valid parameters are flagged as mistakes.
