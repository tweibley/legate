## 2025-12-18 - Empty Plan Fallback Testing

**Gap:** `ADK::Agent`'s fallback behavior when the planner returns an empty plan was untested. The response structure for empty plan errors (`{ details: { status: :error }, last_result: nil }`) is different from execution errors (`{ status: :error }`), which was not obvious without testing.
**Learning:** Error response structures from `ADK::Agent` are inconsistent depending on whether the error occurs during planning (empty plan) or execution (tool error).
**Action:** Added explicit tests for empty plan scenarios to ensure both fallback modes (`:echo` and `:error`) function as intended and to document the response structure.

## 2025-12-17 - [Unhandled Nil in Tool Execution]

**Gap:** `ADK::Tool#execute(nil)` crashes with `NoMethodError` instead of raising a clean error or treating it as empty params.
**Learning:** The method signature `def execute(params = {}, context = nil)` only handles missing arguments, not explicit `nil`.
**Action:** Future reliability improvements should guard against `nil` input in `execute` to prevent crashes.

## 2025-12-19 - Tool Loading Resilience

**Gap:** `ADK::ToolLoader` critical error handling logic (rescuing `SyntaxError` and `StandardError` during file `require`) was completely untested.
**Learning:** `ADK::ToolLoader` uses `require` directly on files discovered via globbing, which means a single malformed file could crash the entire agent boot process if exceptions weren't handled.
**Action:** Added `spec/adk/tool_loader_spec.rb` to verify that the loader gracefully logs errors instead of crashing when encountering bad files.
