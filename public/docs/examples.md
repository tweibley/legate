# Examples Guide

Legate ships with a curated set of examples that walk you through every major feature of the framework. Each example is self-contained and can be run directly from the project root.

```bash
bundle exec ruby examples/01_simple_agent.rb
```

> **Note:** Examples that call the Gemini LLM require a `GOOGLE_API_KEY` environment variable. See `.env.example` for the full list.

---

## Core Examples

These numbered examples form a progressive learning path — start at 00 (the `agent.ask` quickstart) and work your way up.

### Getting Started

#### 00 — Quickstart (`agent.ask`)
`examples/00_quickstart.rb`

The shortest path: define an agent and get an answer with `agent.ask('…').answer`. Shows the `Event` result accessors (`#answer` / `#success?` / `#error_message`), streaming progress via a block, and how to continue a conversation with `session_id:`. Start here.

#### 01 — Simple Agent
`examples/01_simple_agent.rb`

The "hello world" of Legate using the **explicit** lifecycle that `ask` automates: define → instantiate → start → run_task → stop, with a single agent and the built-in Echo tool. Reach for this when you need fine control over sessions and lifecycle.

#### 02 — Multi-Tool Agent
`examples/02_multi_tool_agent.rb`

Registers multiple tools (Echo, Calculator, CatFacts, RandomNumber) on a single agent and demonstrates how the Gemini planner selects the appropriate tool for each request. Also shows agent-to-agent delegation via the built-in `delegate_task` tool.

#### 03 — Custom Tool
`examples/03_custom_tool.rb`

How to build your own tool from scratch using the `Legate::Tool` DSL. Defines parameters with types, implements `perform_execution`, registers the tool globally, uses it both directly and through an agent.

### Core Patterns

#### 04 — Agent Instructions
`examples/04_agent_instructions.rb`

Shows how the `instruction` field acts as a system prompt that guides the planner's behavior. Runs two tasks against the same agent — one that fits the instructions and one that doesn't — to demonstrate how instructions shape agent responses.

#### 05 — State & Sessions
`examples/05_state_and_sessions.rb`

Demonstrates session state management: creating sessions with initial state, reading and writing state from tools via `ToolContext`, scoped state keys (`user:`, `app:`, `temp:`), and inspecting event history after task execution.

#### 06 — Callbacks
`examples/06_callbacks.rb`

Registers all six lifecycle callbacks (`before_agent`, `after_agent`, `before_model`, `after_model`, `before_tool`, `after_tool`) on an agent and logs each invocation. Shows how callbacks can inspect and pass through context, prompts, and tool parameters.

### Async & Jobs

#### 07 — Async Jobs
`examples/07_async_jobs.rb`

Uses the `SleepyTool` (a `BaseAsyncJobTool` subclass) to start a background job, then checks its status with `check_job_status`. Demonstrates the `:pending` → `:success` lifecycle for long-running operations.

### Multi-Agent Systems

#### 08 — Loop Agent
`examples/08_loop_agent.rb`

Creates a `LoopAgent` that runs sub-agents in a cycle until a termination condition is met (or max iterations are reached). Uses a counter agent and a condition-checking agent to demonstrate state-driven loop control.

#### 09 — Sequential Workflow
`examples/09_sequential_workflow.rb`

Defines a pipeline of three agents (data gatherer → data processor → report writer) that execute in order using the `:sequential` agent type. Each agent stores its output via `output_key` for the next agent to consume.

#### 10 — Parallel Workflow
`examples/10_parallel_workflow.rb`

Defines two analyst agents that run concurrently using the `:parallel` agent type. Shows how to fan out work across multiple agents and merge their results.

#### 11 — Agent Delegation
`examples/11_agent_delegation.rb`

Sets up a manager agent that can delegate math problems to a specialist agent using `can_delegate_to`. Demonstrates the agent hierarchy and task handoff pattern.

### Integration

#### 12 — HTTP Client Tool
`examples/12_http_client_tool.rb`

Builds a complete HTTP API tool using the `Legate::Tools::Base::HttpClient` mixin. Connects to JSONPlaceholder to demonstrate GET and POST requests, JSON parsing, and error handling for missing parameters and invalid actions.

#### 13 — Authentication
`examples/13_authentication.rb`

Covers HTTP Bearer authentication end-to-end: creating credentials, exchanging tokens, applying auth to requests, using the Excon middleware, and integrating auth into a custom tool. Uses httpbin.org for live verification.

#### 14 — MCP Client
`examples/14_mcp_client.rb`

Configures an agent to connect to an external MCP server (the `@modelcontextprotocol/server-filesystem` package) via stdio. Shows MCP server configuration, tool discovery, and running tasks that use external MCP tools alongside native Legate tools.

#### 15 — MCP Server
`examples/15_mcp_server.rb`

Wraps the built-in Calculator tool using `LegateToolAdapter` and exposes it on a `fast-mcp` STDIO server. Demonstrates how to make any Legate tool available to external MCP clients.

#### 16 — Webhooks
`examples/16_webhooks.rb`

Sends an HMAC-signed webhook payload to an external URL using the built-in `WebhookTool`. Uses [webhook.site](https://webhook.site) for easy testing. Demonstrates HMAC-SHA256 payload signing, custom headers, and delivery verification.

---

## Advanced Examples

The `examples/advanced/` directory contains deeper explorations of specific subsystems. These are useful as reference but assume familiarity with the core examples above.

### Authentication (`advanced/auth/`)

In-depth authentication patterns beyond the basics in example 13:

| File | Description |
|------|-------------|
| `oauth2_auth.rb` | Full OAuth 2.0 authorization code flow |
| `oidc_auth.rb` | OpenID Connect authentication |
| `service_account.rb` | Service account / client credentials flow |
| `fiber_auth_example.rb` | Non-blocking auth using Ruby Fibers |
| `fiber_oidc_example.rb` | Fiber-based OIDC flow |
| `token_lifecycle_example.rb` | Token refresh, expiry, and lifecycle management |
| `cookie_auth_tool.rb` | Cookie-based authentication |
| `excon_middleware.rb` | Custom Excon middleware for auth |
| `excon_middleware_auth.rb` | Auth-specific Excon middleware |
| `httpbin_bearer_tool.rb` | Bearer auth against httpbin.org |
| `openweather_api.rb` | Real-world API key auth (OpenWeather) |
| `openweather_tool.rb` | Tool wrapping the OpenWeather API |
| `query_param_middleware_test.rb` | Query parameter auth scheme |
| `test_with_httpbin.rb` | Auth integration testing with httpbin |
| `custom_auth_flows_example.rb` | Building custom auth schemes |

### Multi-Agent Systems (`advanced/mas/`)

Additional orchestration patterns beyond examples 08–11:

| File | Description |
|------|-------------|
| `fixed_delegation_example.rb` | Delegation with explicit agent routing |
| `proper_delegation_example.rb` | Production-style delegation patterns |
| `loop_workflow.rb` | Loop agent in a workflow context |
| `mock_planner.rb` | Testing agents with a mock planner |

### MCP (`advanced/mcp/`)

Additional MCP server configurations beyond examples 14–15:

| File | Description |
|------|-------------|
| `mcp_server_rack.rb` | MCP server running on Rack |
| `mcp_server_async.rb` | Async MCP server |
| `mcp_server_async_tools.rb` | MCP server with async tool execution |
| `mcp_server_legate_agent.rb` | Expose a full agent (not just a tool) via MCP |
| `mcp_resource_server_example.rb` | MCP server with resource discovery |
| `legate_mcp_server_resource_example.rb` | Resource handling in MCP servers |

### Webhooks (`advanced/webhooks/`)

End-to-end webhook patterns beyond example 16:

| File | Description |
|------|-------------|
| `webhook_receiver_agent.rb` | Agent that listens for incoming webhooks |
| `webhook_e2e_runner.rb` | End-to-end webhook sender + receiver test |

### Workflows (`advanced/workflows/`)

Complex multi-agent workflow examples:

| File | Description |
|------|-------------|
| `travel_planner_sequential.rb` | 4-agent sequential travel planner with TTY spinners |
| `travel_planner_parallel.rb` | Travel planner with parallel research agents |
| `travel_planner_auto_sequential.rb` | Auto-wired sequential travel planner |
| `task_refinement_loop_agent.rb` | Iterative text refinement using a 3-agent loop |

### Other (`advanced/`)

| File | Description |
|------|-------------|
| `callback_monitoring.rb` | Production-style monitoring with callbacks (metrics, timers, content filtering) |
| `random_calculator.rb` | Multi-step planning with random numbers and calculator |
| `sleep_agent.rb` | Async job agent with manual polling |

---

## Support Files

The `examples/tools/` directory contains shared tool definitions used by the examples:

- `sleepy_tool.rb` — A `BaseAsyncJobTool` subclass that simulates long-running work (used by examples 07 and the advanced sleep agent)
- `oauth2_example.rb` — OAuth2 tool helper for auth examples
