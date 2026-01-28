## 2025-12-18 - ADK::Planner Documentation Gap

**Gap:** `ADK::Planner` was undocumented despite being the central orchestration component for LLM planning. Its return structure was implicit.
**Learning:** Core "brain" components must have explicit contracts documented, especially when they return complex structures like plans parsed from LLM output.
**Action:** Always document return types of service objects that wrap external APIs or perform complex parsing.

## 2025-12-17 - ADK::Tool Contract Clarity

**Gap:** `ADK::Tool#perform_execution` return type is documented as `Object` but the framework expects a structured Hash `{:status, :result}`, leading to potential runtime errors for new tool developers.
**Learning:** Base classes for plugins (like Tools) must rigorously document the contract for abstract methods to prevent integration issues.
**Action:** Document the expected return Hash structure and provide a complete example of a custom tool.


## 2026-01-28 - Mixin API Discoverability

**Gap:** `ADK::Tools::Base::HttpClient` public helpers (`http_get`, etc.) were undocumented, forcing users to read private/protected implementation logic (`make_request`) to understand available options.
**Learning:** Mixins often provide the "sugar" that users interact with. If these public helpers aren't documented, the convenience is lost.
**Action:** Ensure public helper methods in mixins have full YARD documentation, even if they just delegate to a shared internal method.
