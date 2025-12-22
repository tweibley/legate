## 2025-12-17 - [Redis Session Write Optimization]

**Learning:** `ADK::SessionService::Redis#append_event` was re-serializing and re-writing the entire session state to Redis for every event, even if the state (a potentially large JSON object) hadn't changed.
**Action:** Implemented a conditional check: only write `state` to Redis if `event.state_delta` is present. This avoids expensive JSON serialization, encryption, and network I/O for simple conversation events.

## 2025-12-17 - [Double Transform Anti-Pattern]

**Learning:** Discovered a "Double Transform" anti-pattern where a hash was being transformed via `transform_keys` (allocating a new hash) both in a factory method (`from_h`) AND in the constructor (`initialize`), causing redundant object allocations.
**Action:** When creating factory methods, perform minimal extraction and let the constructor handle validation/transformation, or ensure ownership is passed efficiently without redundant copies.

## 2025-12-18 - [Cached Tool Metadata Resolution]

**Learning:** Tool metadata resolution (`tool_metadata`, which infers names and consolidates DSL/legacy attributes) was being recalculated on every tool instantiation. Since tools are instantiated frequently (e.g., every step in `execute_plan` and during planning prompts), this was a significant overhead (~1.03s vs 0.07s for 100k instantiations).
**Action:** Implemented caching for `tool_metadata` using `@_tool_metadata_cache`. Replaced `attr_accessor` with manual setters in `MetadataDsl` to ensure proper cache invalidation when metadata changes. Always look for "static" calculations in hot paths (like class instantiation) that can be memoized.

## 2025-12-22 - [Frozen Constants in Event Validation]

**Learning:** `ADK::Event#initialize` was allocating new Arrays (e.g., `%i[user agent ...]`) for validation on every instantiation. In a system processing high volumes of events, this created unnecessary GC pressure.
**Action:** Extracted validation lists into `frozen` constants. This reduced `Event.new` execution time by ~26%. Always use constants for static validation lists in hot paths.

## 2025-12-22 - [Redundant Transformations in Serialization Loops]

**Learning:** `ADK::Session.from_h` was calling `transform_keys` on every event hash inside a mapping loop, despite `ADK::Event.from_h` being capable of handling string keys. This resulted in O(N) unnecessary hash allocations during session loading.
**Action:** audit deserialization loops to ensure that data is not being transformed (and allocated) redundantly before being passed to a constructor/factory that can accept the raw format.
