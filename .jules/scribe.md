## 2025-12-18 - ADK::Planner Documentation Gap

**Gap:** `ADK::Planner` was undocumented despite being the central orchestration component for LLM planning. Its return structure was implicit.
**Learning:** Core "brain" components must have explicit contracts documented, especially when they return complex structures like plans parsed from LLM output.
**Action:** Always document return types of service objects that wrap external APIs or perform complex parsing.

## 2025-12-17 - ADK::Tool Contract Clarity

**Gap:** `ADK::Tool#perform_execution` return type is documented as `Object` but the framework expects a structured Hash `{:status, :result}`, leading to potential runtime errors for new tool developers.
**Learning:** Base classes for plugins (like Tools) must rigorously document the contract for abstract methods to prevent integration issues.
**Action:** Document the expected return Hash structure and provide a complete example of a custom tool.

## 2025-05-23 - ADK::Agent Runtime Documentation

**Gap:** `ADK::Agent#run_task`, the primary entry point for executing agents, lacked documentation on parameters and return event structure.
**Learning:** Runtime methods that orchestrate complex flows (callbacks, planning, execution) need detailed docs to explain *what* happens during execution, not just signatures.
**Action:** Prioritize documenting the "main loop" or primary execution method of orchestrator classes.
