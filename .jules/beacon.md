## 2025-12-17 - [Unhandled Nil in Tool Execution]

**Gap:** `ADK::Tool#execute(nil)` crashes with `NoMethodError` instead of raising a clean error or treating it as empty params.
**Learning:** The method signature `def execute(params = {}, context = nil)` only handles missing arguments, not explicit `nil`.
**Action:** Future reliability improvements should guard against `nil` input in `execute` to prevent crashes.
