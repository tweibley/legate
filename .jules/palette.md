## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2026-01-31 - CLI Spell Checking for Parameters

**Learning:** When using CLI tools with multiple parameters, typos are common and the default "unknown parameter" warning is unhelpful. Ruby's built-in `did_you_mean` gem is lightweight and effective for these cases.
**Action:** Integrated `DidYouMean::SpellChecker` into `ADK::CLI::ToolCommands#execute`. When an unknown parameter is encountered, check the valid parameters list and offer a "Did you mean?" suggestion. This pattern should be applied to any CLI command accepting dynamic keys.
