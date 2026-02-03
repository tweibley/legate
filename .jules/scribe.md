
## 2025-05-18 - ToolContext Documentation Gap

**Gap:** `ADK::ToolContext` is a critical API for tool authors but lacked usage examples, forcing developers to read the source to understand how to access state or loggers.
**Learning:** Examples are crucial for context objects because their API surface (methods like `state_set`) isn't immediately obvious from just seeing the object passed into a method.
**Action:** When documenting "context" or "environment" objects, always include a full usage example showing the most common interactions (logging, state, user ID).
