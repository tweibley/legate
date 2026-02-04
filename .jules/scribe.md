## 2025-02-18 - Core Class Documentation Gap

**Gap:** `ADK::AgentDefinition`, the central configuration class for agents, lacked class-level documentation.
**Learning:** Core classes used in DSLs often get overlooked because developers focus on method documentation, but the class doc is critical for explaining the DSL context itself.
**Action:** When surveying, prioritize checking the "entry point" classes (like those used in `define` blocks) for missing overview documentation.
