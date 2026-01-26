## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.

## 2026-01-26 - [CLI Command Injection]

**Vulnerability:** A CLI helper method `run_gcloud_command` used backticks with string interpolation (` `gcloud #{command}` `) to execute shell commands. This allowed potential command injection if input parameters weren't perfectly sanitized.
**Learning:** Even internal CLI helpers must use safe execution patterns. String interpolation in backticks is a classic "ticking time bomb" vulnerability.
**Prevention:** Always use `Open3.capture2e` (or similar) with an argument array (`Open3.capture2e('cmd', *args)`) to bypass the shell entirely.
