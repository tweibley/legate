## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2025-05-23 - Did You Mean?

**Learning:** When users mistype a CLI parameter (e.g., `param1` vs `pram1`), the previous behavior was to simply ignore the unknown parameter with a warning. This forced users to manually inspect the tool definition to find the correct spelling.
**Action:** Integrated `DidYouMean::SpellChecker` into `ADK::CLI::ToolCommands`. Now, when an unknown parameter is detected, the CLI suggests the mostly likely intended parameter. This small touch significantly reduces frustration when exploring new tools via the CLI.
