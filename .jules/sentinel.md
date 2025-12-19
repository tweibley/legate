## 2024-05-23 - SSRF Protection in HttpClient

**Vulnerability:** Tools using `ADK::Tools::Base::HttpClient` were vulnerable to Server-Side Request Forgery (SSRF) as they could access private networks (localhost, 10.x.x.x, etc.) and cloud metadata services.
**Learning:** `WebMock` does not intercept `Resolv` calls, so DNS based validation logic executes even in tests using `stub_request`. To properly test SSRF protection without relying on external DNS, one must mock `Resolv` or verify that the protection logic handles resolution failures securely.
**Prevention:** Implemented a centralized `validate_url_security` method in `HttpClient` that resolves hostnames and checks against `PRIVATE_IP_RANGES`. This enforces SSRF protection for all tools including `HttpClient` (like `WebhookTool`).
