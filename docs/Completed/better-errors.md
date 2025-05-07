# Standardized Error Handling for ADK Tools

**Goal:** Improve the developer experience for handling errors within ADK tools by using custom exceptions instead of returning error hashes.

**Problem:** Tools currently return `{ status: :error, error_message: '...' }`, which is boilerplate-heavy and less idiomatic than raising exceptions.

**Solution:** Introduce custom `ADK::ToolError` exceptions that tools can raise. The agent runtime will rescue these exceptions and automatically format the standard error event.

**Plan:**

1.  [DONE] Define Custom Error Classes:
    *   Created `ADK::ToolError` (base class for tool execution errors) in `lib/adk/errors.rb`.
    *   Created `ADK::ToolArgumentError` (inheriting from `ToolError`) for specific argument validation issues.
    *   Added YARD comments.

2.  [DONE] Update Agent Tool Execution Logic (`ADK::Agent`):
    *   Located the code block where `tool.execute` or `tool.perform_execution` is called in `execute_step`.
    *   Wrapped this call in `begin`/`rescue ADK::ToolError => e` blocks.
    *   Inside the `rescue` blocks, construct the standard error event hash (including `:error_class`) using data from the exception `e`.
    *   Ensured this formatted error event is correctly recorded in the session history and propagated correctly to the final agent event content.

3.  [DONE] Refactor Existing Tools:
    *   Reviewed and refactored built-in tools (`lib/adk/tools/`) to raise exceptions.
    *   Reviewed and refactored example tools (`docs/demo-plan.md`) to raise exceptions.

4.  [DONE] Update Tests:
    *   Ran the test suite (`bundle exec rake spec`).
    *   Identified and fixed failing tests by updating expectations from error hashes to raised exceptions (`raise_error` matcher).
    *   Added specific tests to `spec/adk/agent_spec.rb` to verify handling of `ADK::ToolError` and `ADK::ToolArgumentError`.

5.  [DONE] Update Documentation:
    *   Updated `docs/better-user-experience.md` to mark this item as complete.
    *   Updated `README.md` tool development section to mention raising exceptions.
    *   Added YARD comments for the new error classes. 