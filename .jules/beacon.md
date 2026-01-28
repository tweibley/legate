## 2025-12-18 - Empty Plan Fallback Testing

**Gap:** `ADK::Agent`'s fallback behavior when the planner returns an empty plan was untested. The response structure for empty plan errors (`{ details: { status: :error }, last_result: nil }`) is different from execution errors (`{ status: :error }`), which was not obvious without testing.
**Learning:** Error response structures from `ADK::Agent` are inconsistent depending on whether the error occurs during planning (empty plan) or execution (tool error).
**Action:** Added explicit tests for empty plan scenarios to ensure both fallback modes (`:echo` and `:error`) function as intended and to document the response structure.

## 2025-12-17 - [Unhandled Nil in Tool Execution]

**Gap:** `ADK::Tool#execute(nil)` crashes with `NoMethodError` instead of raising a clean error or treating it as empty params.
**Learning:** The method signature `def execute(params = {}, context = nil)` only handles missing arguments, not explicit `nil`.
**Action:** Future reliability improvements should guard against `nil` input in `execute` to prevent crashes.

## 2024-05-22 - [Parameter Coercion Edge Cases]

**Gap:** `ADK::Tool` parameter coercion had undefined behavior for edge cases like float-to-integer truncation and JSON parsing for array/hash types.
**Learning:** `Integer(val)` in Ruby truncates floats (e.g., `12.9` -> `12`) but raises for float-strings (e.g., `"12.9"`). This creates inconsistent behavior depending on input type.
**Action:** Added comprehensive coercion tests (`spec/adk/tool_coercion_spec.rb`) to document and lock in current behavior, preventing accidental regressions or silent data loss.
