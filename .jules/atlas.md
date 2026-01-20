## 2024-05-22 - ADK Configuration Coupling

**Issue:** `ADK::Configuration` eagerly instantiated `RedisStore` and `SessionService` in its `#initialize` method. This forced a dependency on a running Redis server just to load the configuration class or instantiate it for unrelated tests, creating tight coupling between the configuration object and the infrastructure layer.

**Learning:** Eager instantiation of heavy infrastructure dependencies in configuration classes defeats the purpose of "configuration" (which should be metadata) and makes the system brittle and hard to test in isolation.

**Action:** Refactored `ADK::Configuration` to use lazy initialization (memoization) for service dependencies. This allows the configuration object to be lightweight and testable, deferring the infrastructure connection until the service is actually requested.
