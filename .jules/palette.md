## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-24 - Helpful "Did you mean?" Suggestions

**Learning:** When users mistype agent or tool names in the CLI, generic "not found" errors force them to run a separate list command to find the correct name. This breaks their workflow.
**Action:** Enhanced `ADK::CLI::OutputHelper` to use Ruby's `DidYouMean::SpellChecker`. Now, "not found" errors automatically suggest the closest valid agent or tool name, turning a dead-end error into an actionable hint.
