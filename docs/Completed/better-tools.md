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
*   New class methods provided by the DSL:
    *   `tool_description "Your tool description"` (Sets the description)
    *   `parameter :param_name, type: :string, required: true, description: "..."` (Defines a single parameter)
    *   `self.explicit_tool_name = :your_custom_name` (Optional setter to override inferred name)
*   Tool name is inferred from the class name (e.g., `MySpecialTool` becomes `:my_special_tool`) by default.
*   Registration is handled automatically via the `ADK::Tool.inherited` hook, which calls `ADK::GlobalToolManager.register_tool`.
*   The `tool_metadata` class method now consolidates metadata defined via the DSL or the old `define_metadata` method, prioritizing DSL values if both are present.
*   The `effective_tool_name` class method determines the final name (Priority: `explicit_tool_name` -> `define_metadata` name -> inferred name).
*   Original `define_metadata` method remains functional for backward compatibility but issues a deprecation warning.
*   Refactored built-in tools (`Calculator`, `Echo`, `CatFacts`, `RandomNumberTool`, `AgentTool`, `CheckJobStatusTool`, `SleepyTool`) to use the new DSL.
*   Updated relevant specs (`agent_spec.rb`, `global_tool_manager_spec.rb`, individual tool specs) to test the new DSL and registration mechanism, ensuring compatibility with the old method during the transition.

*(This section can be used to document design choices, progress, and examples as we implement these features.)* 