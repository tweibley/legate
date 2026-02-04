## 2025-12-18 - Empty Plan Fallback Testing

**Gap:** `ADK::Agent`'s fallback behavior when the planner returns an empty plan was untested. The response structure for empty plan errors (`{ details: { status: :error }, last_result: nil }`) is different from execution errors (`{ status: :error }`), which was not obvious without testing.
**Learning:** Error response structures from `ADK::Agent` are inconsistent depending on whether the error occurs during planning (empty plan) or execution (tool error).
**Action:** Added explicit tests for empty plan scenarios to ensure both fallback modes (`:echo` and `:error`) function as intended and to document the response structure.

## 2025-12-17 - [Unhandled Nil in Tool Execution]

**Gap:** `ADK::Tool#execute(nil)` crashes with `NoMethodError` instead of raising a clean error or treating it as empty params.
**Learning:** The method signature `def execute(params = {}, context = nil)` only handles missing arguments, not explicit `nil`.
**Action:** Future reliability improvements should guard against `nil` input in `execute` to prevent crashes.


## 2026-02-04 - Tool Parameter Coercion Edge Cases

**Gap:** `ADK::Tool#validate_and_coerce_params` had complex logic for boolean string handling and JSON parsing for arrays/hashes that was not exhaustively tested, leaving potential edge cases uncovered.
**Learning:** Type coercion logic often grows to handle various inputs (LLM hallucinations, HTTP params) but tests often only cover the happy path or standard inputs.
**Action:** Added `spec/adk/tool_coercion_spec.rb` to explicitly test boolean variations and JSON parsing edge cases.
