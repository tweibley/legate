## 2024-05-24 - Documenting Base Class Contracts

**Gap:** The abstract method `ADK::Tool#perform_execution` had sparse documentation regarding its return values, specifically the differing requirements for `:success`, `:error`, and `:pending` states.
**Learning:** For base classes that users are expected to subclass, generic return type documentation is insufficient. Users need to know exactly what keys are required for different outcomes (e.g., `:job_id` for async). Concrete examples for each state are more valuable than a text description.
**Action:** When documenting abstract methods or interfaces, always include separate `@example` blocks for each distinct return state or mode of operation.
