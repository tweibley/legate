## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.

## 2025-05-15 - Command Injection in Private Helper

**Vulnerability:** A private helper method `run_gcloud_command` in the CLI used backticks with interpolated strings (`gcloud #{command}`), allowing command injection. Although the code was currently unreachable (commented out), it posed a latent critical risk.
**Learning:** Security vulnerabilities in "dead" or utility code can be easily revived during refactoring or future feature development. Securing helpers protects future developers.
**Prevention:** Refactored the method to accept an array of arguments and use `Open3.capture2e('cmd', *args)` to bypass shell interpretation entirely.
