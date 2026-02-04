## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-06-18 - CLI Typo Suggestions

**Learning:** Users often mistype agent or tool names in the CLI. The error messages were generic ("not found") and unhelpful. The `did_you_mean` gem (standard in Ruby) can provide helpful suggestions if we have the list of candidates.
**Action:** Enhanced `ADK::CLI::OutputHelper#output_error` to accept metadata (`:tool` or `:agent`) and offer "Did you mean?" suggestions. Also added a `suggestion` field to the JSON output for machine consumption.
