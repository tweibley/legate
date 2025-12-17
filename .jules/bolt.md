## 2025-12-17 - [Redis Session Write Optimization]

**Learning:** `ADK::SessionService::Redis#append_event` was re-serializing and re-writing the entire session state to Redis for every event, even if the state (a potentially large JSON object) hadn't changed.
**Action:** Implemented a conditional check: only write `state` to Redis if `event.state_delta` is present. This avoids expensive JSON serialization, encryption, and network I/O for simple conversation events.
