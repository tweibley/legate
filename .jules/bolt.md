## 2025-12-17 - [Redis Session Write Optimization]

**Learning:** `ADK::SessionService::Redis#append_event` was re-serializing and re-writing the entire session state to Redis for every event, even if the state (a potentially large JSON object) hadn't changed.
**Action:** Implemented a conditional check: only write `state` to Redis if `event.state_delta` is present. This avoids expensive JSON serialization, encryption, and network I/O for simple conversation events.

## 2025-12-17 - [Double Transform Anti-Pattern]

**Learning:** Discovered a "Double Transform" anti-pattern where a hash was being transformed via `transform_keys` (allocating a new hash) both in a factory method (`from_h`) AND in the constructor (`initialize`), causing redundant object allocations.
**Action:** When creating factory methods, perform minimal extraction and let the constructor handle validation/transformation, or ensure ownership is passed efficiently without redundant copies.

## 2025-12-18 - [Cached Tool Metadata Resolution]

**Learning:** Tool metadata resolution (`tool_metadata`, which infers names and consolidates DSL/legacy attributes) was being recalculated on every tool instantiation. Since tools are instantiated frequently (e.g., every step in `execute_plan` and during planning prompts), this was a significant overhead (~1.03s vs 0.07s for 100k instantiations).
**Action:** Implemented caching for `tool_metadata` using `@_tool_metadata_cache`. Replaced `attr_accessor` with manual setters in `MetadataDsl` to ensure proper cache invalidation when metadata changes. Always look for "static" calculations in hot paths (like class instantiation) that can be memoized.

## 2026-01-24 - [ADK::Tool Parameter Validation Optimization]

**Learning:** `ADK::Tool#validate_and_coerce_params` was a hot path with unnecessary object allocations (Hash duplication, Array creation for key checks). In high-frequency tool execution scenarios, simple optimizations like pre-calculating constant data (`@required_parameters`) and avoiding `dup` on already-new hashes can yield significant speedups (observed ~35%).
**Action:** Inspect other core framework components (like `Planner` or `Agent`) for similar "re-calculation of constants" patterns in hot paths.

## 2026-01-24 - [Encapsulation in Optimization]

**Learning:** Exposing internal optimization structures (like `@required_parameters`) via public `attr_reader` to "make it available" violates encapsulation and API stability principles.
**Action:** Keep optimization state internal unless there is a compelling use case for external consumers. Use `run_in_bash_session` to verify API surface area changes are minimal.
