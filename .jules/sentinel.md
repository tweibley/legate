## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.

## 2025-12-19 - [SSRF in Shared HttpClient]

**Vulnerability:** The shared `ADK::Tools::Base::HttpClient` mixin, used by multiple tools, did not enforce SSRF protection by default. While `WebhookTool` had its own protection, other tools using the client (or future tools) would be vulnerable if they accepted user-supplied URLs.
**Learning:** Centralized security logic is critical for shared components. Security features like SSRF protection should be implemented in the lowest common denominator (the base client) rather than relying on individual implementations to remember it.
**Prevention:** Moved the SSRF validation logic from `WebhookTool` into `HttpClient`. Now, `setup_http_client` validates the base URL, and `make_request` validates any absolute target URLs before connection, protecting all tools that use this mixin.
