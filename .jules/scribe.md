## 2025-12-18 - ADK::Planner Documentation Gap

**Gap:** `ADK::Planner` was undocumented despite being the central orchestration component for LLM planning. Its return structure was implicit.
**Learning:** Core "brain" components must have explicit contracts documented, especially when they return complex structures like plans parsed from LLM output.
**Action:** Always document return types of service objects that wrap external APIs or perform complex parsing.

## 2025-12-17 - ADK::Tool Contract Clarity

**Gap:** `ADK::Tool#perform_execution` return type is documented as `Object` but the framework expects a structured Hash `{:status, :result}`, leading to potential runtime errors for new tool developers.
**Learning:** Base classes for plugins (like Tools) must rigorously document the contract for abstract methods to prevent integration issues.
**Action:** Document the expected return Hash structure and provide a complete example of a custom tool.

## 2025-05-21 - ADK::Tool::MetadataDsl Documentation

**Gap:** The `tool_description` and `parameter` DSL methods in `ADK::Tool::MetadataDsl` were undocumented, making it difficult for tool authors to know available options (like `:type`, `:required`, `:description`) without reading source code.
**Learning:** DSLs are the primary user interface for libraries; if they aren't documented with examples, users will struggle to use the library correctly or fully utilizing its features.
**Action:** Ensure all DSL methods have comprehensive YARD documentation with usage examples, especially for `options` hashes.

## 2025-05-21 - Refactoring Cache Invalidation Risks

**Gap:** A documentation change inadvertently introduced a bug by renaming a memoized variable (`@tool_metadata`) while the cache invalidation logic in setter methods still cleared the old variable name (`@_tool_metadata_cache`).
**Learning:** When renaming variables involved in memoization or caching, explicitly grep for all usages (especially in manual setter methods or `nil` assignments) to ensure invalidation logic remains correct.
**Action:** Run comprehensive searches for variable names before renaming them, or verify logic in manual accessors during refactoring.
