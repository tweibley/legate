## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-24 - Agent Name Typos in CLI

**Learning:** When using CLI commands like `adk agent status`, a small typo in the agent name resulted in a generic "not found" error, forcing the user to list all agents to find the correct name.
**Action:** Implemented `suggest_agent_message` helper in `AgentCommands` using `did_you_mean` gem. Now, if an agent definition is not found, the CLI suggests the closest matching available agent name (e.g., "Did you mean 'my_agent'?"), significantly reducing friction for typos.
