# WIP: Automatic Tool Discovery Feature

This file tracks the implementation progress for the automatic tool discovery feature in `ADK::Agent`.

**Goal:** Allow `ADK::Agent` to automatically find, load, register, instantiate, and add tools from specified directories.

**Plan:**

1.  [DONE] Modify `ADK::Agent#initialize`:
    *   Add `tool_paths` keyword argument.
    *   Store initial registered tools.
    *   Iterate `tool_paths`, validate directories.
    *   Find and `require` `*.rb` files (non-recursively).
    *   Handle `LoadError` during `require`.
    *   Determine newly registered tools (Approach B).
    *   Instantiate and add new tools using `GlobalToolManager` and `add_tool`.
2.  [DONE] Implement Helper Method (Optional but Recommended):
    *   Refactor discovery logic into a private `_discover_and_load_tools` method.
3.  [DONE] Update `ADK::GlobalToolManager` (If Necessary):
    *   Verify `registered_tools` and `create_instance` work as expected.
    *   Added `registered_tool_names` method for clarity.
4.  [DONE] Update Demo Project (`adk-news-demo`):
    *   Modify `run_news_agent.rb` to use `tool_paths`.
    *   Remove manual `require` and `add_tool` calls.
    *   Verify demo functionality.
5.  [DONE] Add Unit Tests:
    *   Test initialization with/without `tool_paths`.
    *   Test valid/invalid paths.
    *   Test `LoadError` handling.
    *   Test non-discovery of outside tools.
6.  [DONE] Update Documentation:
    *   Update `docs/better-user-experience.md`.
    *   Add RDoc/YARD comments for `tool_paths`.
    *   Update guides/examples. 