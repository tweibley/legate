## 2025-12-18 - ADK::Planner Documentation Gap

**Gap:** `ADK::Planner` was undocumented despite being the central orchestration component for LLM planning. Its return structure was implicit.
**Learning:** Core "brain" components must have explicit contracts documented, especially when they return complex structures like plans parsed from LLM output.
**Action:** Always document return types of service objects that wrap external APIs or perform complex parsing.

## 2025-12-17 - ADK::Tool Contract Clarity

**Gap:** `ADK::Tool#perform_execution` return type is documented as `Object` but the framework expects a structured Hash `{:status, :result}`, leading to potential runtime errors for new tool developers.
**Learning:** Base classes for plugins (like Tools) must rigorously document the contract for abstract methods to prevent integration issues.
**Action:** Document the expected return Hash structure and provide a complete example of a custom tool.

## 2026-02-06 - ADK::Tools::Base::HttpClient Mixin Discoverability

**Gap:** The README encouraged using `HttpClient` for custom tools, but the mixin's public helpers were undocumented in the source, hiding critical usage details like automatic JSON encoding.
**Learning:** Mixins intended for public use (SDK-style) are part of the public API and need rigorous documentation, even if they are technically "internal" modules.
**Action:** Audit other mixins in `lib/adk/tools/base` for similar documentation gaps.
