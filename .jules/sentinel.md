## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.

## 2026-02-05 - Command Injection in CLI Utilities

**Vulnerability:** Unsafe shell execution in `ADK::CLI::DeploymentCommands#run_gcloud_command` using backticks with string interpolation.
**Learning:** Even helper methods that are currently unused or commented out can be dangerous if they use unsafe patterns (`system("#{cmd}")` or `\`#{cmd}\``). Future developers might uncomment or reuse them without realizing the risk.
**Prevention:** Always use `Open3.capture2e` or `system` with array arguments (`system('cmd', 'arg1')`) to bypass the shell when executing external commands with variable arguments.
