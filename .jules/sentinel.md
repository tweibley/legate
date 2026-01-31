## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.

## 2026-01-31 - [Missing Security Headers in Web App]

**Vulnerability:** The ADK Web App lacked explicit configuration for several critical security headers (e.g., `Referrer-Policy`, `Strict-Transport-Security`), leaving it vulnerable to information leakage and potentially other attacks if framework defaults changed.
**Learning:** Sinatra/Rack apps do not automatically enforce a comprehensive set of security headers. Relying on implicit defaults is risky.
**Prevention:** Explicitly configured a "security headers" block in the global `before` filter of `ADK::Web::App` to enforce `Referrer-Policy`, `X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`, and `HSTS` (conditional on SSL). Added a dedicated spec to verify their presence.
