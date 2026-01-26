## 2025-12-18 - Empty Plan Fallback Testing

**Gap:** `ADK::Agent`'s fallback behavior when the planner returns an empty plan was untested. The response structure for empty plan errors (`{ details: { status: :error }, last_result: nil }`) is different from execution errors (`{ status: :error }`), which was not obvious without testing.
**Learning:** Error response structures from `ADK::Agent` are inconsistent depending on whether the error occurs during planning (empty plan) or execution (tool error).
**Action:** Added explicit tests for empty plan scenarios to ensure both fallback modes (`:echo` and `:error`) function as intended and to document the response structure.

## 2025-12-17 - [Unhandled Nil in Tool Execution]

**Gap:** `ADK::Tool#execute(nil)` crashes with `NoMethodError` instead of raising a clean error or treating it as empty params.
**Learning:** The method signature `def execute(params = {}, context = nil)` only handles missing arguments, not explicit `nil`.
**Action:** Future reliability improvements should guard against `nil` input in `execute` to prevent crashes.

## 2025-12-19 - Parameter Coercion Edge Cases

**Gap:** `ADK::Tool` parameter coercion logic (strings to integers/booleans/JSON) was implemented but lacked dedicated edge case tests.
**Learning:** `Integer(value)` and `Float(value)` in Ruby raise `ArgumentError` for invalid strings, which `ADK::Tool` correctly catches, but this behavior relies on Ruby internals that should be explicitly verified to ensure consistent API behavior (e.g., that "12.34" fails integer coercion instead of truncating).
**Action:** Added comprehensive test suite for `validate_and_coerce_params` covering all supported types and invalid inputs to guarantee stability.
