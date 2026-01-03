## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.


## 2024-05-23 - Command Injection in Deployment CLI

**Vulnerability:** The `ADK::CLI::DeploymentCommands#run_gcloud_command` method used backticks with string interpolation to execute shell commands (`output = \`gcloud #{command} 2>&1\``). The `command` string was constructed using user-supplied inputs (`gcp_project_id`, `gcp_region`) which were not strictly sanitized, allowing for command injection via CLI arguments.
**Learning:** Even internal helper methods in CLI tools must treat arguments as untrusted if they originate from user input. Using backticks or `system` with a single string argument invokes the shell, which interprets metacharacters.
**Prevention:** Use `Open3.capture2e` (or `system` with multiple arguments) to execute commands. Pass the command and its arguments as an array. This bypasses the shell and passes arguments directly to the executable.
