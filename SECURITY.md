# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | Yes       |
| < 0.1   | No        |

## Trust model

Legate is a framework embedded in your application; some inputs are **trusted by design**. Knowing which is essential before deploying it.

### The web UI is unauthenticated by default

`legate web start` serves an admin-grade interface (create agents, run tasks, edit config) with **no application login**. The only built-in gate is optional HTTP Basic Auth via `BASIC_AUTH_USER`/`BASIC_AUTH_PASSWORD`. CSRF is enforced and production requires `SESSION_SECRET`, but neither authenticates users.

**Run it on localhost or a trusted private network.** Do not expose it to untrusted users without your own authentication in front of it. The per-browser `web_user_id` cookie is a convenience identifier, **not** an identity/authorization boundary.

### MCP server configurations are trusted input

Configuring an agent's `mcp_servers` is equivalent to adding a dependency:

- **`:stdio` servers run a local subprocess** from the configured `command`/`args` — arbitrary local command execution is the intended behavior of stdio MCP, not a vulnerability.
- **`:sse`/remote MCP URLs are intentionally not SSRF-restricted**, because MCP servers legitimately run on `localhost`/inside private networks. A hostile MCP URL could reach internal services.

The boundary is **who can supply an agent definition's `mcp_servers`**. In code you control, there is no exposure. The risk only materializes if untrusted users can create/edit agent definitions — which is precisely why the unauthenticated web UI must not be public.

### What is actively guarded

- **Outbound requests are SSRF-guarded.** The `Legate::Auth::UrlGuard` refuses loopback/link-local/private/CGNAT/metadata addresses (including IPv4-mapped IPv6) and fails **closed** when a host won't resolve; it gates the outbound webhook tool and the auth/credential-test calls. The webhook tool additionally **pins** the connection to the pre-validated IP (with the original `Host`/SNI) to defeat DNS rebinding. (MCP is exempt — see above.)
- **Inbound webhooks** verify HMAC-SHA256 signatures with a constant-time comparison.
- **Stored credentials** are encrypted at rest (libsodium / `RbNaCl::SimpleBox`).
- **CSRF** is enforced on all state-changing web requests with a constant-time token compare.

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Email security reports to: **taylor@taylorw.com**

Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact

You can expect an initial response within 72 hours.
