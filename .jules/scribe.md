## 2025-12-18 - ADK::Planner Documentation Gap

**Gap:** `ADK::Planner` was undocumented despite being the central orchestration component for LLM planning. Its return structure was implicit.
**Learning:** Core "brain" components must have explicit contracts documented, especially when they return complex structures like plans parsed from LLM output.
**Action:** Always document return types of service objects that wrap external APIs or perform complex parsing.

## 2025-12-17 - ADK::Tool Contract Clarity

**Gap:** `ADK::Tool#perform_execution` return type is documented as `Object` but the framework expects a structured Hash `{:status, :result}`, leading to potential runtime errors for new tool developers.
**Learning:** Base classes for plugins (like Tools) must rigorously document the contract for abstract methods to prevent integration issues.
**Action:** Document the expected return Hash structure and provide a complete example of a custom tool.

## 2024-05-23 - ADK::AgentDefinition DSL Documentation

**Gap:** `ADK::AgentDefinition` relied on internal `DefinitionProxy` logic for its DSL, making the public API for configuring agents opaque without reading source code.
**Learning:** When using internal proxy objects for DSLs, the public-facing class must document the DSL methods available in the block, as the proxy itself is often private or hidden.
**Action:** Add class-level `@example` blocks showing the full DSL capability when the DSL is implemented via delegation or proxy.
