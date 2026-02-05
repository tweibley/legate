## 2026-02-05 - Split-Brain Error Definitions

**Issue:** Two files defined the same error namespace (`lib/adk/error.rb` and `lib/adk/errors.rb`). `lib/adk/error.rb` was mostly dead code but uniquely defined `ADK::ConfigurationError`, which was used by core components, while `lib/adk/errors.rb` was the main definition file loaded by the gem entry point.
**Learning:** This split likely occurred during a refactor where `errors.rb` was introduced but `error.rb` wasn't fully cleaned up. Tools requiring `../error` were inadvertently relying on the fact that `errors.rb` was already loaded by the main application, masking the issue that `error.rb` didn't actually define the errors they needed (like `ADK::ToolError`).
**Action:** Consolidated all error definitions into `lib/adk/errors.rb`, updated requires in tools to point to the correct file, and deleted the redundant `lib/adk/error.rb`. This enforces a single source of truth for error definitions.
