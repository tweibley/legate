## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.

## 2025-12-19 - [Command Injection in CLI Helper]

**Vulnerability:** A CLI helper method `run_gcloud_command` used backticks with string interpolation to execute shell commands. Although some call sites were commented out, the method was vulnerable if used with unsanitized user input (e.g., project ID).
**Learning:** Even helper methods in CLI tools must be secure by default, as they might be reused or uncommented by future developers. Backticks invocations (` `) are unsafe when arguments are dynamic.
**Prevention:** Refactored to use `Open3.capture2e` which bypasses the shell when provided with an array of arguments, preventing command injection regardless of input content.
