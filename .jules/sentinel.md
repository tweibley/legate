## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.


## 2026-01-30 - [SSRF in Authentication Routes]

**Vulnerability:** Found unvalidated user-supplied URLs being passed directly to `Net::HTTP` in `AuthenticationRoutes` testing endpoints.
**Learning:** The application exposes testing endpoints that allow arbitrary outbound HTTP requests, creating an SSRF vector if not validated. SSRF protection was implemented in isolation within `WebhookTool` but not reused.
**Prevention:** Centralized URL validation logic into `ADK::SecurityUtils` and enforced it on all endpoints accepting arbitrary URLs. Always validate destination IPs before making requests to user-provided URLs.
