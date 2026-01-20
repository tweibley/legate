## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.
## 2026-01-20 - Duplicated Redis Initialization

**Issue:** Multiple classes were directly instantiating `Redis.new(ADK.redis_options)`, creating duplication and making it hard to manage connections or mock them in tests.
**Learning:** Centralizing common infrastructure logic (like Redis connections) into a helper method (`ADK.redis_client`) simplifies the codebase and improves testability. However, caution is needed when refactoring code that is heavily mocked in tests, as it requires updating all relevant mocks.
**Action:** Use `ADK.redis_client` for all Redis connections. When refactoring infrastructure code, grep for usages first and anticipate test failures in mocked dependencies.
## 2026-01-20 - Handling Nil Defaults in Helpers

**Issue:** The initial implementation of `ADK.redis_client` assumed `@redis_options` was always a Hash, leading to potential crashes when it was `nil` (uninitialized).
**Learning:** When creating helper methods that wrap configuration or state, always defensive code against `nil` values. Use accessor methods (which might have lazy loading or defaults) instead of raw instance variables. In Ruby, `(hash_or_nil || {}).merge(other)` is a standard safe pattern.
**Action:** Reviewed and fixed `ADK.redis_client` to safely handle `nil` defaults and added specific unit tests to cover this case.
