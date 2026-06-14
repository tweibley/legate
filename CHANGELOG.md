# Changelog

## 0.1.0 / 2026-06-14

First public release of **Legate** — a Ruby framework for building and commanding
AI agents: Gemini LLM integration, tool execution, session management, MCP support,
authentication, a CLI, and a web UI.

### Agents & execution
- Agent lifecycle, task execution, and a definition DSL (`Legate::AgentDefinition`).
- Agent types: LLM agents and Sequential / Parallel / Loop workflow agents.
- Multi-agent systems: agent hierarchies, delegation, and specialized workflow agents.
- Six lifecycle callbacks (before/after agent, model, and tool).
- Ergonomic API: `Agent#ask("…").answer` one-liner; `Event#answer` / `#success?` / `#error?` / `#error_message`.

### Planning & LLM providers
- LLM-powered planning that generates and executes multi-step plans.
- Two strategies: plan-then-execute (default) and an agentic **ReAct** loop (observe → think → act, one tool at a time, recovering from tool errors).
- Pluggable LLM adapters (`Legate::LLM::Adapter`): Gemini (default, `gemini-3.5-flash`) and a local Ollama adapter — swappable without changing agents.
- Structured-output planning (Gemini `responseSchema`) and native function calling where the provider supports it.
- Planning failures return a clean error result with the real reason — with API keys scrubbed from error messages and logs (`Legate::Redaction`).

### Tools
- `Legate::Tool` base class with a metadata DSL and typed parameters.
- Built-in tools: `http_request` (SSRF-safe, auth-aware HTTP client), `read_webpage` (fetch a page as readable text), `current_time`, `calculator`, `cat_facts`, `echo`, `delegate_task`, `webhook_tool`, and async job helpers.
- HTTP-client base (`Tools::Base::HttpClient`) with a shared SSRF guard (`Tools::Base::SafeUrl`) — blocks private/loopback/link-local/CGNAT targets and pins the connection to the validated IP to defeat DNS rebinding.
- Global and per-agent tool registries; `use_tool` accepts a class or a name; a "did you mean?" suggestion on unknown tools; opt-in typed `Legate::ToolResult`; `Legate.tools` introspection.
- MCP client/server adapters for interoperability with external tools and agents.
- Auto-loading of custom tools and agents from conventional directories on `legate web start`.

### Sessions, events & streaming
- Immutable event model (user / tool request / tool result / agent) with scoped session state.
- In-memory session store by default; opt-in durable `SessionService::ActiveRecord` that survives restarts. `require 'legate'` never loads ActiveRecord.
- Event streaming via `Agent#run_task(on_event:)` and Server-Sent Events (`POST /agents/:name/stream`).

### Authentication
- Schemes: API Key, Bearer, OAuth2, OIDC, and Service Account.
- Token lifecycle (acquisition, storage, expiration, refresh), credential management, and URL → scheme mappings.
- Opt-in credential encryption (`LEGATE_AUTH_ENCRYPTION_KEY`); a web UI and testing dashboard for schemes, credentials, and mappings.

### Web UI
- Branded Sinatra + Slim + HTMX interface — a ruby-gem-in-laurel "Legion Commander" identity, fixed left sidebar, Space Grotesk / Inter typography, and full light + dark themes.
- A command-console agents dashboard, a three-zone chat/run view (transcript + tool-call timeline + run-details inspector), agent Config / Tools / Authentication tabs, and a documentation browser.
- AI builders: describe an agent → review → **Add to Legion** live (no download or restart); a **"Suggested tools to create"** handoff; **Save to `agents/`** to persist runtime agents; and optional **live tool install** gated by `Legate.config.allow_runtime_tool_load` (default ON outside production) with an explicit confirmation and server-side validation.
- Security hardening: site-wide CSRF protection (token applied to every `fetch`/HTMX request), output escaping on all dynamic `innerHTML` sinks, and optional HTTP Basic Auth (`BASIC_AUTH_USER`/`BASIC_AUTH_PASSWORD`).

### CLI
- `legate skaffold` project generator and `legate web start`.
- Agent/tool lifecycle commands (create, start, stop, status, execute, export) with `--json` / `--quiet` flags and session identity.
- AI generation (`legate agent ai-generate`, `legate tool ai-generate`, pipe-friendly), authentication-management commands, and deployment generation (Docker / Cloud Run).

### Integrations & deployment
- Rails: `require 'legate/rails'` adds a Railtie and a `rails generate legate:install` generator; ActiveJob background runs are a documented pattern.
- Webhooks: an inbound listener with validators (HMAC, custom) and dynamic agent triggering, plus outbound webhook helpers.
- Container deployment (Ruby 3.4, Puma); in-memory storage by default.

### Requirements
- Ruby >= 3.4. A `GOOGLE_API_KEY` is required for Gemini-powered planning and generation.
