## 2025-12-18 - ADK::Planner Documentation Gap

**Gap:** `ADK::Planner` was undocumented despite being the central orchestration component for LLM planning. Its return structure was implicit.
**Learning:** Core "brain" components must have explicit contracts documented, especially when they return complex structures like plans parsed from LLM output.
**Action:** Always document return types of service objects that wrap external APIs or perform complex parsing.
