## 2025-12-18 - Empty Plan Fallback Testing

**Gap:** `ADK::Agent`'s fallback behavior when the planner returns an empty plan was untested. The response structure for empty plan errors (`{ details: { status: :error }, last_result: nil }`) is different from execution errors (`{ status: :error }`), which was not obvious without testing.
**Learning:** Error response structures from `ADK::Agent` are inconsistent depending on whether the error occurs during planning (empty plan) or execution (tool error).
**Action:** Added explicit tests for empty plan scenarios to ensure both fallback modes (`:echo` and `:error`) function as intended and to document the response structure.

## 2025-12-17 - [Unhandled Nil in Tool Execution]

**Gap:** `ADK::Tool#execute(nil)` crashes with `NoMethodError` instead of raising a clean error or treating it as empty params.
**Learning:** The method signature `def execute(params = {}, context = nil)` only handles missing arguments, not explicit `nil`.
**Action:** Future reliability improvements should guard against `nil` input in `execute` to prevent crashes.

## 2025-12-18 - [Tool Parameter Coercion Coverage]

**Gap:** `ADK::Tool` parameter coercion logic (specifically `coerce_value`) was implicitly tested via other tests but lacked dedicated, exhaustive edge-case coverage for types like Boolean (string variants) and JSON structures.
**Learning:** Private methods like `coerce_value` are critical for reliability when processing LLM outputs, but often get overlooked in unit tests that focus on "happy path" execution of specific tools.
**Action:** When testing core framework components that handle external input (like tools), create focused specs that exercise validation logic in isolation using anonymous subclasses, ensuring all type coercion paths are verified.
