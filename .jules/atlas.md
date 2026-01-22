## 2024-05-22 - Lazy Initialization for Infrastructure

**Issue:** `ADK::Configuration` eagerly initialized `RedisStore` and `RedisSessionService`, forcing network connections on startup and complicating tests.
**Learning:** Default values in `initialize` that instantiate heavy dependencies create implicit coupling and side effects.
**Action:** Switched to lazy initialization (memoization) for `definition_store` and `session_service` to defer connection until access.
