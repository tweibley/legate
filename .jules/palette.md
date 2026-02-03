## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-24 - Context-Aware Error Suggestions

**Learning:** Generic "not found" errors for agents and tools are a major friction point in CLI usage, especially with typo-prone names. The default behavior often leaves users guessing if the item exists or if the name is wrong.
**Action:** Enhanced `ADK::CLI::OutputHelper` to use the `did_you_mean` gem. By leveraging metadata passed to error methods (`metadata: { agent: name }`), we can provide specific "Did you mean '...'" suggestions by dynamically querying the `AgentDefinitionStore` and `GlobalToolManager`. This turns a dead-end error into an actionable hint without cluttering the main logic.
