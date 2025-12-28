## 2025-12-18 - Empty Plan Fallback Testing

**Gap:** `ADK::Agent`'s fallback behavior when the planner returns an empty plan was untested. The response structure for empty plan errors (`{ details: { status: :error }, last_result: nil }`) is different from execution errors (`{ status: :error }`), which was not obvious without testing.
**Learning:** Error response structures from `ADK::Agent` are inconsistent depending on whether the error occurs during planning (empty plan) or execution (tool error).
**Action:** Added explicit tests for empty plan scenarios to ensure both fallback modes (`:echo` and `:error`) function as intended and to document the response structure.

## 2025-12-17 - [Unhandled Nil in Tool Execution]

**Gap:** `ADK::Tool#execute(nil)` crashes with `NoMethodError` instead of raising a clean error or treating it as empty params.
**Learning:** The method signature `def execute(params = {}, context = nil)` only handles missing arguments, not explicit `nil`.
**Action:** Future reliability improvements should guard against `nil` input in `execute` to prevent crashes.


## 2025-12-28 - Missing Configuration Class Coverage

**Gap:** The `ADK::Configuration` class was completely untested, despite being a critical central point for the application's configuration. It initializes connection classes for Redis and sets defaults.
**Learning:** Simple configuration classes are often overlooked because they seem "too simple to fail" or "just data holders". However, they often contain logic (initialization of other services) or default values that, if changed, could break the system.
**Action:** Always verify that "simple" data classes or configuration objects have unit tests covering their defaults and initialization logic, especially if they instantiate external connections.
