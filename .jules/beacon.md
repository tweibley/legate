## 2025-12-18 - Empty Plan Fallback Testing

**Gap:** `ADK::Agent`'s fallback behavior when the planner returns an empty plan was untested. The response structure for empty plan errors (`{ details: { status: :error }, last_result: nil }`) is different from execution errors (`{ status: :error }`), which was not obvious without testing.
**Learning:** Error response structures from `ADK::Agent` are inconsistent depending on whether the error occurs during planning (empty plan) or execution (tool error).
**Action:** Added explicit tests for empty plan scenarios to ensure both fallback modes (`:echo` and `:error`) function as intended and to document the response structure.

## 2025-12-17 - [Unhandled Nil in Tool Execution]

**Gap:** `ADK::Tool#execute(nil)` crashes with `NoMethodError` instead of raising a clean error or treating it as empty params.
**Learning:** The method signature `def execute(params = {}, context = nil)` only handles missing arguments, not explicit `nil`.
**Action:** Future reliability improvements should guard against `nil` input in `execute` to prevent crashes.


## 2025-12-19 - Parameter Coercion Coverage

**Gap:** `ADK::Tool#validate_and_coerce_params` had complex logic for JSON parsing (Array/Hash) and Boolean strings that was completely uncovered by unit tests.
**Learning:** Relying on subclass tests (like `Calculator` testing only Numeric) leaves the base class's broader type coercion logic vulnerable to regressions.
**Action:** Centralized parameter coercion tests in `spec/adk/tool_parameter_coercion_spec.rb` to ensure all supported types (Boolean, Array, Hash) are rigorously tested independently of tool implementations.
