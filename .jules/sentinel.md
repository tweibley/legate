## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.

## 2025-12-21 - [Implicit SSRF Protection Missing in HttpClient]

**Vulnerability:** `ADK::Tools::Base::HttpClient` is documented (in agent memory) as having centralized SSRF protection, but the implementation is actually isolated in `ADK::Tools::WebhookTool`.
**Learning:** Developers relying on `HttpClient` for new tools might assume they inherit SSRF protection, leaving them vulnerable. Documentation and memory must align with the code.
**Prevention:** Move the `validate_url_security` logic from `WebhookTool` to `HttpClient` (as a future task) to ensure defense-in-depth for all HTTP-capable tools.

## 2025-12-21 - [Missing Web Security Headers]

**Vulnerability:** The Sinatra Web UI lacked standard security headers (`X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy`), increasing risk of clickjacking and XSS.
**Learning:** Sinatra defaults (via `Rack::Protection`) might not set strict enough values or all recommended headers (e.g. `Referrer-Policy`). Explicit configuration ensures compliance.
**Prevention:** Added a `before` filter in `ADK::Web::App` to explicitly set these headers on every response.
