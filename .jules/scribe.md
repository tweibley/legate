## 2025-12-18 - ADK::Planner Documentation Gap

**Gap:** `ADK::Planner` was undocumented despite being the central orchestration component for LLM planning. Its return structure was implicit.
**Learning:** Core "brain" components must have explicit contracts documented, especially when they return complex structures like plans parsed from LLM output.
**Action:** Always document return types of service objects that wrap external APIs or perform complex parsing.

## 2025-12-17 - ADK::Tool Contract Clarity

**Gap:** `ADK::Tool#perform_execution` return type is documented as `Object` but the framework expects a structured Hash `{:status, :result}`, leading to potential runtime errors for new tool developers.
**Learning:** Base classes for plugins (like Tools) must rigorously document the contract for abstract methods to prevent integration issues.
**Action:** Document the expected return Hash structure and provide a complete example of a custom tool.

## 2025-12-19 - ADK::ToolContext Usage Clarity

**Gap:** `ADK::ToolContext` had methods for state management (`state_get`, `state_set`) but lacked explanation on *how* they persist data (pending until success) or *why* to use them over instance variables.
**Learning:** Context objects are often "black boxes" to developers. Documenting them reveals the "superpowers" available to the plugin developer (like shared session state).
**Action:** When documenting context/environment objects, use `@example` tags to show practical usage of the exposed capabilities.
