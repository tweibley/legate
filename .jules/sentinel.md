## 2024-02-23 - [Fixed Command Injection in Deployment CLI]

**Vulnerability:** Command injection vulnerability in `ADK::CLI::DeploymentCommands#run_gcloud_command` and `#create_gcloud_config`. User-provided inputs (e.g., project ID, region) were interpolated directly into a shell command string executed via backticks or `system`. This allowed attackers to execute arbitrary commands by injecting shell metacharacters (e.g., `test; echo PWNED`).

**Learning:** Even internal helper methods that seem "safe" or "unused" (or commented out code blocks) can harbor vulnerabilities. The usage of backticks (`` `cmd` ``) or `system("cmd string")` with interpolated variables is inherently risky in Ruby. Always assume input can be malicious, even if sanitization attempts exist elsewhere.

**Prevention:** Always use `Open3.capture2e` (or `system` with array arguments) when executing external commands. Pass arguments as an array (`['cmd', 'arg1', 'arg2']`) to bypass the shell and prevent injection. If a legacy method must support string arguments, explicitly parse them using `Shellwords.split` before execution, but prefer refactoring to array-only interfaces.
