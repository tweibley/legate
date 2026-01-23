## 2025-12-18 - Script Generation Injection

**Vulnerability:** User input was interpolated into a generated Bash script inside double quotes (`VAR="#{input}"`). Malicious input containing quotes could break out and execute arbitrary commands when the user runs the script.
**Learning:** `Shellwords.escape` is essential not just for `system()` calls but also when generating shell scripts programmatically.
**Prevention:** Use `Shellwords.escape(input)` and remove surrounding quotes in the target script template (e.g., `VAR=#{escaped_input}`).

## 2025-12-17 - [SSRF in WebhookTool]

**Vulnerability:** `ADK::Tools::WebhookTool` allowed agents to send HTTP requests to any URL, including `localhost` and private IPs.
**Learning:** Tools that accept URLs as input must explicitly validate the destination to prevent Server-Side Request Forgery (SSRF), especially given the agent's ability to explore networks.
**Prevention:** Implemented `validate_url_security` using `Resolv` and `IPAddr` to block access to private, loopback, and link-local addresses. This pattern should be applied to any future tools making outbound HTTP requests.


## 2025-05-23 - Unsafe Deserialization Pattern

**Vulnerability:** Used `Marshal.load(Marshal.dump(obj))` for deep copying internal objects. While not directly exploitable with untrusted input in this context, it promotes unsafe `Marshal` usage and can lead to RCE if the pattern spreads to handling user input.
**Learning:** `Marshal` is often used as a lazy deep copy mechanism in Ruby, but it carries significant security risks and performance overhead. It also fails on non-serializable objects (IO, Proc).
**Prevention:** Use a dedicated `deep_copy` utility or `clone`/`dup` logic appropriate for the data structure. Avoid `Marshal` entirely unless strictly necessary for trusted serialization.
