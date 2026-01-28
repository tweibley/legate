## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2025-01-28 - Extracting Job Enqueuing Logic

**Issue:** `ADK::Web::WebhookListener` had a large route handler mixing routing, validation, transformation, and job enqueuing logic.
**Learning:** Sinatra route blocks can easily become bloated if business logic (like Sidekiq enqueuing) isn't extracted early.
**Action:** Extract logic into private methods (like `enqueue_job_to_sidekiq`) to keep the route handler focused on HTTP concerns.
