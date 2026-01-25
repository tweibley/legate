## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.


## 2024-05-23 - Command Injection in Deployment Commands

**Vulnerability:** `ADK::CLI::DeploymentCommands` was vulnerable to command injection in `create_gcloud_config`. User-provided `project_id` and `region` (and `config_name`) were interpolated directly into shell strings executed via backticks.
**Learning:** Even in CLI tools intended for local use, input validation and sanitization are critical, especially when inputs can come from configuration files or indirect user input. `gsub` sanitization on one variable (`config_name`) is good, but all interpolated variables must be treated as unsafe or escaped for defense in depth.
**Prevention:** Always use `Shellwords.escape` (or `system` with array arguments) when constructing shell commands with variable interpolation. Prefer `system` with array arguments over backticks or `system` with a string whenever possible to avoid shell parsing entirely.
