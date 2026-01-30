## 2025-02-18 - Sidekiq Worker Complexity

**Issue:** `ADK::WebhookJobWorker#perform` was over 100 lines long and highly complex due to mixed responsibilities (validation, initialization, execution) and extensive error handling.
**Learning:** Background workers often accumulate "retryable vs non-retryable" error handling logic, which bloats the main execution method. This pattern makes the code hard to read and test.
**Action:** Refactor workers by extracting the core logic into a separate method (e.g., `perform_job_logic`) and keeping `perform` strictly for high-level orchestration and error handling. Isolate payload validation and service initialization into private helper methods.
