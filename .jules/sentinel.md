## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.

## 2026-01-27 - [MEDIUM] Verbose Logging of Secrets

**Vulnerability:** The HTTP client module (`ADK::Tools::Base::HttpClient`) and `WebhookTool` were logging sensitive information (API keys, tokens, authorization headers) in plain text. Query parameters in URLs were logged at INFO level, and request headers/parameters were logged at DEBUG level.
**Learning:** Logging logic often overlooks that "debug" information can contain secrets. URL query parameters are often considered safe to log, but often contain credentials.
**Prevention:** Always implement redaction logic for any logging that includes URLs or request/response headers and bodies. Use a centralized redaction helper.
