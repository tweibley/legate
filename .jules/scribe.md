## 2025-12-18 - ADK::Planner Documentation Gap

**Gap:** `ADK::Planner` was undocumented despite being the central orchestration component for LLM planning. Its return structure was implicit.
**Learning:** Core "brain" components must have explicit contracts documented, especially when they return complex structures like plans parsed from LLM output.
**Action:** Always document return types of service objects that wrap external APIs or perform complex parsing.

## 2025-12-17 - ADK::Tool Contract Clarity

**Gap:** `ADK::Tool#perform_execution` return type is documented as `Object` but the framework expects a structured Hash `{:status, :result}`, leading to potential runtime errors for new tool developers.
**Learning:** Base classes for plugins (like Tools) must rigorously document the contract for abstract methods to prevent integration issues.
**Action:** Document the expected return Hash structure and provide a complete example of a custom tool.


## 2026-01-19 - ADK::Tool::MetadataDsl Documentation Gap

**Gap:** The DSL for defining tools (`parameter`, `tool_description`) was undocumented in the code, forcing developers to rely on external guides or examples.
**Learning:** DSL modules are the primary user interface for defining behavior; documenting them inline makes the API discoverable via IDEs and generated docs.
**Action:** Prioritize documenting DSL methods (`ClassMethods`) when they are the main way users interact with a framework component.
