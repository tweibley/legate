## 2026-01-16 - Documenting Tool Metadata DSL

**Gap:** The methods `tool_description` and `parameter` in `ADK::Tool::MetadataDsl` lacked documentation, making it harder for users to know how to define tools.
**Learning:** Automated refactoring tools like Rubocop can sometimes introduce subtle regressions (e.g., changing `@parameters_definition` to `@initialize_dsl_storage` when auto-correcting `Naming/MemoizedInstanceVariableName`).
**Action:** Always verify automated refactorings manually, especially when variable names are involved, and avoid mixing functional refactorings with documentation updates if possible to isolate risks.
