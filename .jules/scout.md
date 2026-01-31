## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2024-05-22 - Default Rubocop MethodLength is Strict

**Issue:** The default Rubocop `Metrics/MethodLength` is set to 10 lines, which is very strict. Many methods in the codebase violate this, creating a lot of noise.
**Learning:** While small methods are good, a 10-line limit often forces artificial splitting of cohesive logic. The codebase has many violations, suggesting the team might benefit from a slightly higher limit (e.g., 20 or 25) or just accepts these violations.
**Action:** When refactoring, aim for cohesion first. If a method is 15-20 lines but does one thing clearly, it's better than 3 fragmented 5-line methods.
