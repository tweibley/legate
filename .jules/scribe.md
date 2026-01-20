## 2025-02-18 - Documenting DSL Methods

**Gap:** The `tool_description` and `parameter` DSL methods in `ADK::Tool::MetadataDsl` were undocumented.
**Learning:** DSL methods often appear "magical" to users. Documenting them with `@example` tags is critical because users interact with them directly when defining classes, often more frequently than standard instance methods.
**Action:** When surveying for documentation gaps, specifically check modules included/extended into user-facing classes for undocumented DSL methods.
