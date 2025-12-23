## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.


## 2025-12-23 - [Sinatra Vulnerability CVE-2024-21510]

**Vulnerability:** Sinatra 3.2.0 is vulnerable to CVE-2024-21510 (reliance on untrusted inputs in security decision).
**Learning:** Fixing this requires upgrading to Sinatra >= 4.1.0, which is a major version bump and potentially breaking change. We rejected this fix in favor of a non-breaking security enhancement (headers) to adhere to the "Ask First" boundary for breaking changes.
**Prevention:** Schedule a dedicated task for upgrading Sinatra major version and testing for regressions.
