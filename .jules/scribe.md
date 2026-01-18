## 2025-12-18 - ADK::Planner Documentation Gap

**Gap:** `ADK::Planner` was undocumented despite being the central orchestration component for LLM planning. Its return structure was implicit.
**Learning:** Core "brain" components must have explicit contracts documented, especially when they return complex structures like plans parsed from LLM output.
**Action:** Always document return types of service objects that wrap external APIs or perform complex parsing.

## 2025-12-17 - ADK::Tool Contract Clarity

**Gap:** `ADK::Tool#perform_execution` return type is documented as `Object` but the framework expects a structured Hash `{:status, :result}`, leading to potential runtime errors for new tool developers.
**Learning:** Base classes for plugins (like Tools) must rigorously document the contract for abstract methods to prevent integration issues.
**Action:** Document the expected return Hash structure and provide a complete example of a custom tool.


## 2024-05-22 - Undocumented DSL Methods

**Gap:** `ADK::Tool::MetadataDsl` methods (`tool_description`, `parameter`) were completely undocumented, forcing developers to read source code to understand how to define tools.
**Learning:** DSL modules are the primary interface for users but often get overlooked in documentation passes because they are "internal" modules mixed into classes. Also, RuboCop's autocorrect for `Naming/MemoizedInstanceVariableName` can break logic if applied to initialization methods (like `initialize_dsl_storage`), renaming variables that are not actually memoized accessors.
**Action:** Prioritize documenting DSL modules as they are the user-facing API. Always review RuboCop autocorrect changes for logic regressions, especially variable renames.
