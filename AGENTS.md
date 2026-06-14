# AGENTS.md

Guidance for AI coding agents (and humans) working in the **Legate** repository.

Legate is a Ruby framework for building AI agents: Gemini-powered planning, tool
execution, sessions, MCP, an authentication subsystem, a CLI, and a web UI.
Ruby >= 3.4. The source of truth for behavior is the test suite in `spec/`.

## Quick reference

```bash
bundle install                 # install dependencies
bundle exec rspec              # run the full test suite (must pass, 0 failures)
bundle exec rubocop            # lint (CI fails on ANY offense)
bundle exec rake sass          # compile web/public/styles/main.scss -> main.css
bundle exec legate web start   # start the web UI on http://localhost:4567
gem build legate.gemspec       # build the gem
```

## Running tests

- The full suite must pass with **0 failures** and RuboCop must be **clean** — CI
  gates on both, plus `bundle-audit` and a gem build.
- **Run tests with no API key set.** CI has no `GOOGLE_API_KEY` / `GEMINI_API_KEY`,
  so a test that depends on a live LLM passes locally but fails in CI. Reproduce
  the CI environment before you commit:

  ```bash
  env -u GEMINI_API_KEY -u GOOGLE_API_KEY bundle exec rspec
  ```

- **Never hit the real LLM API in tests** — mock `Legate::LLM` / the Gemini
  adapter (see `spec/legate/planner_spec.rb`).
- Reset global state between tests with `Legate::GlobalToolManager.reset!`.
- Run one file: `bundle exec rspec spec/legate/agent_spec.rb`.

## Project layout

```
lib/legate/
  agent.rb            # Agent lifecycle + AgentDefinition DSL
  planner.rb          # LLM planning — plan-then-execute (default) + :react loop
  tool.rb             # Base Tool class + typed-parameter DSL
  tools/              # Built-in tools (echo, calculator, http_request, ...)
  tools/base/         # HttpClient mixin + SafeUrl (SSRF guard)
  session.rb          # Session state + immutable event history
  session_service/    # In-memory (default) + ActiveRecord (opt-in, durable)
  tool_context.rb     # Execution context passed to tools (state, auth)
  llm/                # Adapter interface + Gemini (default) + Ollama
  auth/               # Schemes, credentials, URL mappings, UrlGuard
  mcp/                # Model Context Protocol client/server
  web/                # Sinatra + Slim + HTMX UI (opt-in via require 'legate/web')
  cli/                # Thor CLI commands
  generators/         # AI-powered agent/tool code generation
spec/                 # mirrors lib/
examples/             # numbered learning path (00–16) + examples/advanced/
public/docs/          # the documentation site
```

`require 'legate'` loads only the core; the web stack and CLI are opt-in, so don't
add hard requires from core onto `web/` or `cli/`.

## Adding a tool

```ruby
class MyTool < Legate::Tool
  tool_description 'What this tool does'
  parameter :input, type: :string, required: true

  private

  def perform_execution(params, context)
    # params: validated Hash with symbol keys; context: Legate::ToolContext
    { status: :success, result: '...' }   # or { status: :error, error_message: '...' }
  end
end
```

- `perform_execution` **must return a Hash** with `status: :success | :error | :pending`.
- Parameter types: `:string`, `:integer`, `:float`/`:numeric`, `:boolean`, `:array`, `:hash`.
- Tool names are **Symbols** (`:my_tool`), inferred from the class name.
- Ship a tool as a default by adding it to the registration list in `lib/legate.rb`;
  project-local tools call `Legate::GlobalToolManager.register_tool(MyTool)`.
- Tools that fetch arbitrary URLs **must** validate through `Tools::Base::SafeUrl`
  (the SSRF guard) — see `lib/legate/tools/http_request_tool.rb` for the pattern.

## Adding an agent

```ruby
definition = Legate::AgentDefinition.new.define do |a|
  a.name :my_agent          # Symbol, required
  a.instruction 'You are…'  # required — validation fails without it
  a.use_tool :calculator
end
Legate::GlobalDefinitionRegistry.register(definition)
```

## Conventions & gotchas

- **Names are Symbols**, not Strings (`:echo`, not `'echo'`).
- **Events are frozen** — immutable after creation.
- **Call `agent.start` before `run_task`** (MCP connections initialize during start).
- **Workflow sub-agents** must be registered in `GlobalDefinitionRegistry` first.
- **Session-scoped keys** use `user:` / `app:` / `temp:` prefixes; plain keys stay
  in the session's internal map.
- **Version is single-sourced** in `lib/legate/version.rb`; the gemspec derives it.
  Bump it **before** tagging — `release.yml` verifies the tag matches the gemspec.
- **Web UI styles**: edit `lib/legate/web/public/styles/main.scss`, never
  `main.css`; run `bundle exec rake sass` and commit the compiled `main.css` too.

## Before you commit

1. `env -u GEMINI_API_KEY -u GOOGLE_API_KEY bundle exec rspec` — 0 failures.
2. `bundle exec rubocop` — 0 offenses.
3. Touched SCSS? `bundle exec rake sass` and commit `main.css`.
4. Use conventional commit messages (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`).

See [CONTRIBUTING.md](CONTRIBUTING.md) for the human-facing contribution guide and
`public/docs/` for the full documentation.
