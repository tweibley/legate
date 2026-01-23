## 2025-12-18 - ADK::Planner Documentation Gap

**Gap:** `ADK::Planner` was undocumented despite being the central orchestration component for LLM planning. Its return structure was implicit.
**Learning:** Core "brain" components must have explicit contracts documented, especially when they return complex structures like plans parsed from LLM output.
**Action:** Always document return types of service objects that wrap external APIs or perform complex parsing.

## 2025-12-17 - ADK::Tool Contract Clarity

**Gap:** `ADK::Tool#perform_execution` return type is documented as `Object` but the framework expects a structured Hash `{:status, :result}`, leading to potential runtime errors for new tool developers.
**Learning:** Base classes for plugins (like Tools) must rigorously document the contract for abstract methods to prevent integration issues.
**Action:** Document the expected return Hash structure and provide a complete example of a custom tool.


## 2026-01-23 - ADK::Agent Entry Point Documentation

**Gap:** `ADK::Agent#run_task` is the primary entry point for agent execution but was undocumented, leaving users to guess the required parameters and session service interface.
**Learning:** Even if internal logic is complex, the public API entry point must be crystal clear to lower the barrier to entry.
**Action:** Prioritize documenting the "main" method that users interact with first.
