## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.


## 2026-01-18 - Prevent Information Leakage in Error Responses

**Vulnerability:** Information Leakage in Web UI and Webhook Listener.
Internal error messages (exceptions) were being returned directly to the user in JSON responses and HTML views. This could expose internal paths, class names, and potentially sensitive data contained in exception messages.

**Learning:** `rescue => e` with `e.message` in the response is a common anti-pattern. While convenient for debugging during development, it is dangerous in production.

**Prevention:** Always catch exceptions at the boundary and return generic error messages to the user. Log the detailed exception (message + backtrace) for server-side debugging.
