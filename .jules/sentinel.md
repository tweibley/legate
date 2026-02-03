## 2026-02-03 - [Missing Security Headers in Sinatra App]

**Vulnerability:** The Sinatra web application was missing the `Referrer-Policy` header, and while other headers were likely set by defaults/middleware, they were not explicitly enforced.
**Learning:** Framework defaults (like `Sinatra::Base` or `rack-protection`) may provide some security headers but often miss newer or stricter ones like `Referrer-Policy`. Implicit reliance on defaults makes the security posture opaque.
**Prevention:** Explicitly configure critical security headers in a `before` block or dedicated middleware configuration to ensure they are present and set to desired values, regardless of underlying framework updates or default changes. Always verify with tests.
