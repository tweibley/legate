## 2024-02-14 - Fix Command Injection in GCloud Deployment

**Vulnerability:** Command injection in `ADK::CLI::DeploymentCommands#run_gcloud_command`. User input (project ID) was interpolated directly into a backtick execution string (`gcloud #{command}`), allowing execution of arbitrary commands if malicious input was provided.
**Learning:** `system` with an array of arguments bypasses the shell, which prevents injection but also breaks shell builtins like `command -v`. When checking for command existence, a static string passed to `system` is safe and necessary to invoke the shell for builtins.
**Prevention:** Use `Open3.capture2e` with an array of arguments for all command executions that involve variable input. Avoid string interpolation in system calls or backticks.
