## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.

## 2025-10-18 - [CRITICAL] Command Injection in Deployment CLI

**Vulnerability:** Found a command injection vulnerability in `ADK::CLI::DeploymentCommands#run_gcloud_command`. The method used backticks with string interpolation (` `gcloud #{command}` `), allowing attackers to execute arbitrary commands if the `command` argument contained shell metacharacters (e.g., `version; rm -rf /`).
**Learning:** Even in CLI tools intended for local use, using shell interpolation is dangerous. Input might come from untrusted sources (e.g., project names, config values). The vulnerability existed because the helper method was designed to take a raw command string rather than a list of arguments.
**Prevention:** Always use `Open3.capture2e` (or `system`) with an *array* of arguments to prevent shell expansion. Avoid backticks and `system(string)` when arguments are variable. Refactored the helper to accept an array of arguments and enforced this pattern.
