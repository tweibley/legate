## 2025-12-18 - Empty Plan Fallback Testing

**Gap:** `ADK::Agent`'s fallback behavior when the planner returns an empty plan was untested. The response structure for empty plan errors (`{ details: { status: :error }, last_result: nil }`) is different from execution errors (`{ status: :error }`), which was not obvious without testing.
**Learning:** Error response structures from `ADK::Agent` are inconsistent depending on whether the error occurs during planning (empty plan) or execution (tool error).
**Action:** Added explicit tests for empty plan scenarios to ensure both fallback modes (`:echo` and `:error`) function as intended and to document the response structure.

## 2025-12-17 - [Unhandled Nil in Tool Execution]

**Gap:** `ADK::Tool#execute(nil)` crashes with `NoMethodError` instead of raising a clean error or treating it as empty params.
**Learning:** The method signature `def execute(params = {}, context = nil)` only handles missing arguments, not explicit `nil`.
**Action:** Future reliability improvements should guard against `nil` input in `execute` to prevent crashes.

## 2025-12-19 - [Implicit Parameter Coercion Risks]

**Gap:** `ADK::Tool` performs complex implicit coercion (e.g., parsing JSON strings for Array/Hash types, mapping "yes"/"no" to Booleans) which was not exhaustively tested.
**Learning:** Custom coercion logic over standard Ruby types introduces non-obvious edge cases (e.g., invalid JSON strings) that simple "happy path" tests miss.
**Action:** Implemented a dedicated coercion test suite `spec/adk/tool_coercion_spec.rb` to lock down behavior for all supported types and invalid inputs.
