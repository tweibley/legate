# Improving ADK-Ruby Tool Definition & Registration

This document tracks efforts to make defining and registering tools in `adk-ruby` easier and more intuitive.

## Proposed Enhancements

*   [X] **Concise Metadata DSL:**
    *   Reduce verbosity in the `define_metadata` block.
    *   Explore inferring the tool name from the class name (e.g., `MyTool` -> `:my_tool`).
    *   Simplify the `parameters` hash syntax, potentially using type hints or conventions.
    *   Implemented via `description`, `parameter`, and optional `name` class methods in `ADK::Tool::MetadataDsl`.
    *   Name is inferred from class name unless explicitly overridden with `name :my_name`.
    *   Old `define_metadata` is deprecated with a warning.

*   [ ] **Simplified Parameter Access:**
    *   Allow accessing tool parameters as keyword arguments directly in the `execute` method signature (e.g., `def execute(param1:, param2:)`).
    *   Potentially add automatic type checking based on metadata.

*   [ ] **Base Classes/Modules for Common Patterns:**
    *   Provide base classes or modules for common integrations (e.g., `ADK::Tools::HttpClient`, `ADK::Tools::GeminiClient`) to handle boilerplate like API key management, request/response flow, etc.

*   [ ] **Context-Aware Logging:**
    *   Inject a pre-configured logger into tool instances that automatically includes context (like the tool name).

*   [ ] **Standardized Error Handling:** *(Already partially implemented)*
    *   Ensure consistent use of `ADK::ToolArgumentError` and `ADK::ToolError` for error reporting.
    *   Verify the runtime catches and formats these errors correctly into error events.

## Implementation Notes & Decisions

### Concise Metadata DSL (Completed)

*   Introduced `ADK::Tool::MetadataDsl` module included in `ADK::Tool`.
*   New class methods:
    *   `description "Your tool description"`
    *   `parameter :param_name, type: :string, required: true, description: "..."`
    *   `name :explicit_tool_name` (Optional: overrides inferred name)
*   Tool name is inferred from the class name (e.g., `MySpecialTool` -> `:my_special_tool`) by default.
*   Registration is handled via the `inherited` hook in `ADK::Tool`, calling `ADK::GlobalToolManager.register_tool` which uses the `tool_metadata` method from the DSL.
*   Original `define_metadata` logs a deprecation warning but still functions for backward compatibility during transition.
*   Refactored built-in tools (`Calculator`, `Echo`, `CatFacts`, `RandomNumberTool`, `AgentTool`, `CheckJobStatusTool`, `SleepyTool`) and relevant tests (`tool_spec.rb`) to use the new DSL.

*(This section can be used to document design choices, progress, and examples as we implement these features.)* 