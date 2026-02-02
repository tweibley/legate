## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2026-02-02 - Graceful "Did You Mean?" Suggestions

**Learning:** Users frequently mistype agent or tool names in the CLI. Providing a suggestion saves them a round-trip to `list` commands.
**Action:** Enhanced `ADK::CLI::OutputHelper#output_error` to optionally accept `metadata` (e.g., `{ agent: 'name' }`) and use the `did_you_mean` gem to append suggestions.
**Critical Detail:** The implementation uses `defined?` checks and rescues `LoadError` for `did_you_mean` to ensure this is a strictly additive, non-breaking enhancement that degrades gracefully if dependencies are missing.
