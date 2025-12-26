## 2025-12-18 - Empty Plan Fallback Testing

**Gap:** `ADK::Agent`'s fallback behavior when the planner returns an empty plan was untested. The response structure for empty plan errors (`{ details: { status: :error }, last_result: nil }`) is different from execution errors (`{ status: :error }`), which was not obvious without testing.
**Learning:** Error response structures from `ADK::Agent` are inconsistent depending on whether the error occurs during planning (empty plan) or execution (tool error).
**Action:** Added explicit tests for empty plan scenarios to ensure both fallback modes (`:echo` and `:error`) function as intended and to document the response structure.

## 2025-12-17 - [Unhandled Nil in Tool Execution]

**Gap:** `ADK::Tool#execute(nil)` crashes with `NoMethodError` instead of raising a clean error or treating it as empty params.
**Learning:** The method signature `def execute(params = {}, context = nil)` only handles missing arguments, not explicit `nil`.
**Action:** Future reliability improvements should guard against `nil` input in `execute` to prevent crashes.

## 2025-12-25 - Tool Metadata Name Inference and Caching

**Gap:** `ADK::Tool::MetadataDsl` uses `Module.instance_method(:name).bind(self).call` to infer tool names, which bypasses RSpec mocks on `.name`. This makes testing name inference with anonymous classes or doubles tricky without `stub_const`. Additionally, legacy and DSL-based parameter definitions share the same storage variable, leading to silent merging of parameters rather than strict overriding.
**Learning:** When testing metaprogramming that relies on class names, `stub_const` is essential to provide a "real" name to the class. Also, the legacy and DSL implementations for tool metadata are not fully isolated, which can lead to unexpected merging behavior if both are used.
**Action:** Created `spec/adk/tool/metadata_dsl_spec.rb` using `stub_const` to correctly test inference and document the merging behavior.
