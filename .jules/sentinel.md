## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.


## 2026-01-24 - SSRF in Development Tools

**Vulnerability:** Unrestricted URL testing endpoint allowed Server-Side Request Forgery (SSRF), exposing internal services (like localhost:6379) to attackers.
**Learning:** Even "testing" or "development" tools bundled in a library/agent can be exposed if deployed in a production web context. Input validation (allowlisting/blocklisting) is crucial for any feature that accepts a URL and makes a request.
**Prevention:** Use a dedicated `valid_public_url?` helper that resolves DNS and checks against private IP ranges (using `IPAddr#private?`) before initializing any `Net::HTTP` request.
