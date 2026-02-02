## 2025-12-18 - ADK::Planner Documentation Gap

**Gap:** `ADK::Planner` was undocumented despite being the central orchestration component for LLM planning. Its return structure was implicit.
**Learning:** Core "brain" components must have explicit contracts documented, especially when they return complex structures like plans parsed from LLM output.
**Action:** Always document return types of service objects that wrap external APIs or perform complex parsing.

## 2025-12-17 - ADK::Tool Contract Clarity

**Gap:** `ADK::Tool#perform_execution` return type is documented as `Object` but the framework expects a structured Hash `{:status, :result}`, leading to potential runtime errors for new tool developers.
**Learning:** Base classes for plugins (like Tools) must rigorously document the contract for abstract methods to prevent integration issues.
**Action:** Document the expected return Hash structure and provide a complete example of a custom tool.


## 2024-05-23 - Misleading Agent Definition Example

**Gap:** The YARD documentation for `ADK::Agent.define` contained an example using incorrect assignment syntax (`a.name = '...'`) and referenced non-existent methods (`discover_tools_in`), likely from a legacy API version.
**Learning:** `ADK::Agent.define` delegates to `ADK::AgentDefinition::DefinitionProxy`, which strictly uses method call syntax (`name :symbol`). Also, `define` returns an `AgentDefinition` object, not an initialized `Agent`.
**Action:** When documenting DSLs, verify the syntax by checking the underlying proxy/builder class implementation and return types.
