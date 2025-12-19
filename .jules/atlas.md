## 2024-05-24 - Missing Interface Implementation in Redis Service

**Issue:** `ADK::SessionService::Redis` did not implement `get_state` and `set_state`, despite inheriting from `Base` which defines them. This caused `ToolContext#state_get` and MAS output storage to fail when using Redis persistence, violating Liskov Substitution Principle.
**Learning:** Abstractions must be enforced. The `ToolContext` relied on `session_service` behaving consistently, but `Redis` implementation was incomplete. Also, `ADK::Event` roles are strictly validated, requiring explicit addition of `:system` role for internal state update events.
**Action:** Implemented `get_state` and `set_state` in `Redis` service. `set_state` uses `append_event` with a `:system` role to ensure atomic state updates via the existing optimistic locking mechanism.
