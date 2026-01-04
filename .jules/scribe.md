## 2024-05-24 - Agent Class Confusion

**Gap:** The documentation for `ADK::Agent` was confusing because it contained two conflicting class-level comments: one describing the runtime behavior and another (incorrectly) describing the static definition (which belongs to `ADK::AgentDefinition`).

**Learning:** Developers (and LLMs) can easily be confused about where to look for "Agent" logic if the documentation blurs the line between "definition time" (configuration) and "runtime" (execution). Explicitly stating "The Agent class is the runtime counterpart to {ADK::AgentDefinition}" helps clarify this architectural separation.

**Action:** When documenting classes that have a split Definition/Instance pattern (common in Ruby DSLs), always cross-reference the counterpart class and explicitly define the responsibility of the current class (e.g., "Runtime orchestrator" vs "Static configuration").
