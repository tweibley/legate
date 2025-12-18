## 2024-05-23 - Empty Plan Fallback Testing

**Gap:** `ADK::Agent`'s fallback behavior when the planner returns an empty plan was untested. The response structure for empty plan errors (`{ details: { status: :error }, last_result: nil }`) is different from execution errors (`{ status: :error }`), which was not obvious without testing.
**Learning:** Error response structures from `ADK::Agent` are inconsistent depending on whether the error occurs during planning (empty plan) or execution (tool error).
**Action:** Added explicit tests for empty plan scenarios to ensure both fallback modes (`:echo` and `:error`) function as intended and to document the response structure.
