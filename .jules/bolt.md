## 2025-12-17 - [Redis Session Write Optimization]

**Learning:** `ADK::SessionService::Redis#append_event` was re-serializing and re-writing the entire session state to Redis for every event, even if the state (a potentially large JSON object) hadn't changed.
**Action:** Implemented a conditional check: only write `state` to Redis if `event.state_delta` is present. This avoids expensive JSON serialization, encryption, and network I/O for simple conversation events.

## 2025-05-20 - [Double Transform Anti-Pattern]

**Learning:** Discovered a "Double Transform" anti-pattern where a hash was being transformed via `transform_keys` (allocating a new hash) both in a factory method (`from_h`) AND in the constructor (`initialize`), causing redundant object allocations.
**Action:** When creating factory methods, perform minimal extraction and let the constructor handle validation/transformation, or ensure ownership is passed efficiently without redundant copies.

