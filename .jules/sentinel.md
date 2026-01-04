## 2024-02-14 - [Command Injection in CLI Deployment]

**Vulnerability:** The `ADK::CLI::DeploymentCommands#run_gcloud_command` method used backticks (`\``) with interpolated strings constructed from user input (project IDs, regions) to execute `gcloud` commands.
**Learning:** Even internal CLI tools used by developers can be vectors for command injection if they process untrusted input (e.g., from configuration files or command line arguments). `Open3.capture2e` with an argument array is safer and easier to test than backticks or `system` with string interpolation.
**Prevention:** Refactored the method to use `Open3.capture2e` and accept an array of arguments, preventing shell interpretation of the inputs. Added `require 'open3'` to ensure availability.
## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.

