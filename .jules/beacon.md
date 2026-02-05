## 2025-12-18 - Empty Plan Fallback Testing

**Gap:** `ADK::Agent`'s fallback behavior when the planner returns an empty plan was untested. The response structure for empty plan errors (`{ details: { status: :error }, last_result: nil }`) is different from execution errors (`{ status: :error }`), which was not obvious without testing.
**Learning:** Error response structures from `ADK::Agent` are inconsistent depending on whether the error occurs during planning (empty plan) or execution (tool error).
**Action:** Added explicit tests for empty plan scenarios to ensure both fallback modes (`:echo` and `:error`) function as intended and to document the response structure.

## 2025-12-17 - [Unhandled Nil in Tool Execution]

**Gap:** `ADK::Tool#execute(nil)` crashes with `NoMethodError` instead of raising a clean error or treating it as empty params.
**Learning:** The method signature `def execute(params = {}, context = nil)` only handles missing arguments, not explicit `nil`.
**Action:** Future reliability improvements should guard against `nil` input in `execute` to prevent crashes.

## 2025-12-19 - [Partial Coverage via Specialized Specs]

**Gap:** `ADK::ToolContext` had extensive tests for authentication (`spec/adk/tool_context_auth_spec.rb`) but completely lacked coverage for its core state management methods (`state_get`, `state_set`, `state_update`).
**Learning:** Testing files named `*_auth_spec.rb` can create a false sense of security that the entire class is covered, masking the absence of general unit tests. Also, testing `Logger` calls that use blocks requires specific RSpec syntax (`expect { |b| logger.error(&b) }`) rather than standard argument matching.
**Action:** Always check for a general `*_spec.rb` file even if specialized test files exist. Use block capture patterns when testing performance-optimized logging calls.
