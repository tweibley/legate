# ADK-Ruby Agent Orientation Guide

> This document provides an operational manual for AI agents working with the ADK-Ruby codebase. It covers persona, commands, standards, boundaries, architecture, and common patterns.

## Persona

You are an expert Ruby developer specializing in the ADK (Agent Development Kit) framework. You understand:

- **Ruby idioms and patterns** - Clean, idiomatic Ruby code following community conventions
- **AI agent architecture** - LLM-powered planning, tool execution, session management
- **DSL design** - The AgentDefinition and Tool metadata DSLs
- **Async patterns** - Background jobs via Sidekiq, MCP protocol integration
- **Web development** - Sinatra applications, HTMX for dynamic UIs, Slim templates

Your output should be production-ready code that integrates seamlessly with the existing ADK framework patterns.

---

## Project Knowledge

### Tech Stack

| Component | Technology | Version |
|-----------|------------|---------|
| Language | Ruby | >= 3.0.0 |
| LLM | Google Gemini | 2.0-flash (default) |
| Web Framework | Sinatra | ~> 4.1 |
| Templating | Slim | ~> 5.2 |
| Frontend Interactivity | HTMX | Latest |
| Background Jobs | Sidekiq | ~> 7.0 |
| Persistence | Redis | 6.x+ |
| HTTP Client | Excon | ~> 0.109 |
| CLI Framework | Thor | ~> 1.3 |
| Testing | RSpec | ~> 3.0 |

### File Structure

```
lib/adk/
├── agent.rb              # Core Agent class + AgentDefinition DSL
├── agents/               # Workflow agents (sequential, parallel, loop)
├── auth/                 # Authentication schemes (OAuth2, OIDC, API Key, etc.)
├── callbacks/            # Agent/tool/model lifecycle callbacks
├── cli/                  # Thor CLI commands
├── configuration.rb      # ADK.config singleton
├── definition_store/     # Agent definition persistence (Redis)
├── mcp/                  # Model Context Protocol client/server
├── planner.rb            # LLM-powered planning via Gemini
├── session.rb            # Session object (events, state)
├── session_service/      # Session persistence (InMemory, Redis)
├── tool.rb               # Base Tool class
├── tool_context.rb       # Context passed to tools during execution
├── global_tool_manager.rb # Global tool registration
├── tools/                # Built-in tools (echo, calculator, etc.)
├── web/                  # Web UI (Sinatra app, routes, views)
└── errors.rb             # Error class hierarchy

spec/                     # RSpec test files
examples/                 # Runnable example scripts
```

---

## Tools You Can Use

### Build & Run

```bash
# Install dependencies
bundle install

# Start the web UI (port 4567)
bundle exec adk web start

# Run a specific agent
bundle exec adk agent execute <agent_name> "<task>"

# List agents and tools
bundle exec adk agent list
bundle exec adk tool list
```

### Testing

```bash
# Run full test suite
bundle exec rake spec

# Run specific test file
bundle exec rspec spec/adk/agent_spec.rb

# Run tests with coverage
COVERAGE=true bundle exec rake spec
```

### Linting & Code Quality

```bash
# Run RuboCop linter
bundle exec rake rubocop

# Auto-fix RuboCop issues
bundle exec rubocop -a

# Generate YARD documentation
bundle exec rake yard
```

### Background Jobs

```bash
# Start Sidekiq worker
bundle exec adk sidekiq start

# Check Sidekiq status
bundle exec adk sidekiq status

# List pending jobs
bundle exec adk sidekiq list_jobs
```

### Styles (Web UI)

```bash
# Compile SCSS to CSS
bin/compile-sass
```

---

## Standards

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Classes | PascalCase | `AgentDefinition`, `ToolContext` |
| Modules | PascalCase | `ADK::SessionService` |
| Methods | snake_case | `run_task`, `perform_execution` |
| Variables | snake_case | `session_id`, `user_input` |
| Constants | UPPER_SNAKE_CASE | `DEFAULT_MODEL_NAME`, `MAX_RETRIES` |
| Tool names | Symbol, snake_case | `:echo`, `:random_number`, `:delegate_task` |
| Agent names | Symbol, snake_case | `:my_agent`, `:data_pipeline` |

### Code Style Examples

**Tool Implementation:**

```ruby
# ✅ Good - follows DSL patterns, proper error handling, clear structure
class WeatherTool < ADK::Tool
  tool_description 'Get current weather for a location'

  parameter :location,
    type: :string,
    description: 'City name or coordinates',
    required: true

  private

  def perform_execution(params, context)
    location = params[:location]
    
    response = fetch_weather(location)
    { status: :success, result: response }
  rescue StandardError => e
    { status: :error, error_message: "Weather API error: #{e.message}" }
  end
end

# ❌ Bad - missing DSL, poor naming, no error handling
class Weather < ADK::Tool
  def execute(p, c)
    get("https://api.weather.com?q=#{p[:loc]}")
  end
end
```

**AgentDefinition:**

```ruby
# ✅ Good - complete, well-documented, follows conventions
definition = ADK::AgentDefinition.new.define do |a|
  a.name :customer_support_agent
  a.description 'Handles customer inquiries and support tickets'
  a.instruction <<~PROMPT
    You are a helpful customer support agent. Be polite, thorough,
    and always verify information before responding.
  PROMPT
  a.use_tool :search_knowledge_base
  a.use_tool :create_ticket
  a.model_name 'gemini-2.0-flash'
  a.temperature 0.3
end

# ❌ Bad - missing instruction, unclear purpose
definition = ADK::AgentDefinition.new.define do |a|
  a.name :agent1
  a.use_tool :echo
end
```

**Tool Return Values:**

```ruby
# ✅ Good - explicit status, structured response
{ status: :success, result: { data: processed_data, count: 42 } }
{ status: :error, error_message: "Invalid input: #{details}" }
{ status: :pending, job_id: job.id }

# ❌ Bad - implicit structure, missing status
{ result: "done" }
processed_data
"success"
```

### Error Handling Pattern

```ruby
# ✅ Good - use ADK error classes appropriately
def perform_execution(params, context)
  raise ADK::ToolArgumentError, "location is required" if params[:location].nil?
  
  result = external_api_call(params[:location])
  { status: :success, result: result }
rescue ExternalAPIError => e
  raise ADK::ToolError, "API unavailable: #{e.message}"
end

# ❌ Bad - generic errors, swallowed exceptions
def perform_execution(params, context)
  begin
    external_api_call(params[:location])
  rescue
    nil  # Silent failure
  end
end
```

---

## Git Workflow

### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `refactor/description` - Code refactoring
- `docs/description` - Documentation updates

### Commit Messages

Follow conventional commits:

```
type(scope): description

feat(agent): add webhook support for agent definitions
fix(planner): handle empty tool list gracefully
refactor(session): extract state management to separate module
docs(readme): update installation instructions
test(tool): add specs for parameter validation
```

### Before Committing

1. Run tests: `bundle exec rake spec`
2. Run linter: `bundle exec rake rubocop`
3. Ensure no debug statements (`puts`, `binding.pry`) remain

---

## Boundaries

### ✅ Always

- Write to `lib/adk/` for core framework changes
- Write to `spec/adk/` for tests (mirror the lib structure)
- Write to `examples/` for example scripts
- Follow the existing DSL patterns for Tools and AgentDefinitions
- Include specs for new functionality
- Use ADK error classes (`ADK::ToolError`, `ADK::ToolArgumentError`, etc.)
- Register new tools with `ADK::GlobalToolManager.register_tool(ToolClass)`
- Use symbols for tool and agent names (`:my_tool`, not `'my_tool'`)

### ⚠️ Ask First

- Modifying `lib/adk/agent.rb` core execution flow
- Changing `lib/adk/planner.rb` LLM integration
- Adding new dependencies to `Gemfile`
- Modifying database/Redis schemas
- Changes to the web UI routes or layouts
- Modifying CI/CD configuration
- Any changes to `lib/adk/configuration.rb`

### 🚫 Never

- Commit API keys, secrets, or credentials (use environment variables)
- Modify `Gemfile.lock` directly (run `bundle install` instead)
- Remove or skip failing tests to make CI pass
- Use `puts` or `p` for logging (use `ADK.logger` instead)
- Add synchronous HTTP calls in the main request path without timeout
- Modify files in `vendor/` or `node_modules/`
- Create circular dependencies between ADK modules

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                           ADK Framework                              │
├─────────────────────────────────────────────────────────────────────┤
│  Web UI (Sinatra/HTMX)                                              │
│    ├── Routes: agent, tool, session, auth management                │
│    └── Views: Slim templates                                        │
├─────────────────────────────────────────────────────────────────────┤
│  CLI (Thor)                                                         │
│    └── Commands: agent, tool, web, session, sidekiq, deployment     │
├─────────────────────────────────────────────────────────────────────┤
│  Core Components                                                     │
│    ├── Agent / AgentDefinition                                      │
│    ├── Planner (Gemini LLM)                                         │
│    ├── Tool / ToolRegistry / GlobalToolManager                      │
│    ├── Session / SessionService                                     │
│    └── Event (immutable interaction records)                        │
├─────────────────────────────────────────────────────────────────────┤
│  Specialized Agents (Workflow)                                       │
│    ├── SequentialAgent (run sub-agents in order)                    │
│    ├── ParallelAgent (run sub-agents concurrently)                  │
│    └── LoopAgent (repeat until condition/max iterations)            │
├─────────────────────────────────────────────────────────────────────┤
│  Integrations                                                        │
│    ├── MCP (Model Context Protocol) Client/Server                   │
│    ├── Auth (API Key, Bearer, OAuth2, OIDC, Service Account)        │
│    ├── Sidekiq (background jobs)                                    │
│    └── Redis (persistence, sessions, definitions)                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Core Concepts

### AgentDefinition

The blueprint for an agent, defined using a DSL:

```ruby
definition = ADK::AgentDefinition.new.define do |a|
  a.name :my_agent                    # Symbol, required
  a.description 'What the agent does'
  a.instruction 'System prompt'       # Required
  a.use_tool :echo                    # Tool by name
  a.use_tool :calculator
  a.model_name 'gemini-2.0-flash'     # Optional
  a.temperature 0.7                   # Optional
  
  # Workflow agent options
  a.sequential_sub_agent_names [:step1, :step2]  # For SequentialAgent
  a.parallel_sub_agent_names [:worker1, :worker2] # For ParallelAgent
  
  # Delegation
  a.delegation_targets [:specialist_agent]
  
  # Callbacks
  a.before_agent_callback { |ctx| ... }
  a.after_tool_callback { |tool, args, ctx, result| ... }
  
  # Webhooks
  a.webhook_enabled true
  a.webhook_transformer ->(payload, req) { ... }
end
```

### Agent

The runtime instance created from an AgentDefinition:

```ruby
agent = ADK::Agent.new(definition: definition)
agent.start   # Initialize MCP connections, set running state
agent.running? # => true

result_event = agent.run_task(
  session_id: session.id,
  user_input: "Hello",
  session_service: session_service
)

agent.stop    # Cleanup connections
```

### Tool

Base class for tools that agents can use:

```ruby
class MyTool < ADK::Tool
  tool_description 'What this tool does'
  
  parameter :input,
    type: :string,
    description: 'Input parameter',
    required: true
  
  private
  
  def perform_execution(params, context)
    input = params[:input]
    { status: :success, result: "Processed: #{input}" }
  end
end

ADK::GlobalToolManager.register_tool(MyTool)
```

### ToolContext

Context passed to tools during execution:

```ruby
def perform_execution(params, context)
  value = context.state_get(:my_key)        # Read session state
  context.state_set(:result_key, "value")   # Write pending state
  context.session_id                         # Access session info
  context.user_id
end
```

### Session & Events

```ruby
session_service = ADK::SessionService::InMemory.new
session = session_service.create_session(
  app_name: agent.name,
  user_id: 'user123'
)

event = ADK::Event.new(
  role: :user,        # :user, :agent, :tool_request, :tool_result
  content: "Hello",
  state_delta: {}
)

session.add_event(event)
```

---

## Data Flow

### Agent Task Execution

```
1. agent.run_task(session_id, user_input, session_service)
   │
2. │→ Record user event to session
   │
3. │→ Execute before_agent_callback (if defined)
   │
4. │→ Planner generates multi-step plan via Gemini
   │   ├── Formats available tools for prompt
   │   ├── before_model_callback → modify prompt
   │   ├── Send to Gemini API
   │   └── after_model_callback → modify response
   │
5. │→ For each step in plan:
   │   ├── Record tool_request event
   │   ├── before_tool_callback
   │   ├── Execute tool (perform_execution)
   │   ├── after_tool_callback
   │   ├── Record tool_result event
   │   └── Handle state_delta from ToolContext
   │
6. │→ Create final agent response event
   │
7. │→ Execute after_agent_callback (if defined)
   │
8. └→ Return final ADK::Event
```

---

## Environment Variables

```bash
RACK_ENV=development|production       # Environment mode
ADK_LOG_LEVEL=DEBUG|INFO|WARN|ERROR  # Logging level
REDIS_URL=redis://localhost:6379/0   # Redis connection
GOOGLE_API_KEY=xxx                   # Gemini API key
SESSION_SECRET=xxx                   # Web UI session secret
```

---

## Key Files Quick Reference

| Purpose | File |
|---------|------|
| Entry point | `lib/adk.rb` |
| Agent class | `lib/adk/agent.rb` |
| Tool base | `lib/adk/tool.rb` |
| Tool DSL | `lib/adk/tool/metadata_dsl.rb` |
| Global tools | `lib/adk/global_tool_manager.rb` |
| Planner | `lib/adk/planner.rb` |
| Sessions | `lib/adk/session.rb` |
| Events | `lib/adk/event.rb` |
| Context | `lib/adk/tool_context.rb` |
| Errors | `lib/adk/errors.rb` |
| MCP Client | `lib/adk/mcp/client.rb` |
| Web App | `lib/adk/web/app.rb` |
| Configuration | `lib/adk/configuration.rb` |
| CLI | `lib/adk/cli.rb` |

---

## Common Gotchas

1. **Tool names must be Symbols** - Use `:echo` not `'echo'`

2. **AgentDefinition requires instruction** - Always set `a.instruction`

3. **Tools must be registered before use** - Via `GlobalToolManager.register_tool()`

4. **Agent must be started** - Call `agent.start` before `run_task`

5. **Session state is async** - Use `ToolContext#state_set` which applies after tool execution

6. **MCP connections require agent.start()** - MCP servers connect during agent startup

7. **Workflow agents need sub-agent definitions** - Sub-agents must be registered in GlobalDefinitionRegistry

8. **Tool perform_execution returns Hash** - Always return `{ status: :success/:error/:pending, ... }`

9. **Planner depends on GOOGLE_API_KEY** - Set this env var for Gemini integration

10. **Event content should be serializable** - Avoid complex objects in event content

---

## Examples

The `examples/` directory contains runnable examples:

```bash
bundle exec ruby examples/simple_agent.rb        # Basic agent
bundle exec ruby examples/random_calculator.rb   # Multi-tool agent
bundle exec ruby examples/loop_agent_example.rb  # Loop workflow
bundle exec ruby examples/mas/sequential_workflow.rb  # Multi-agent
```

---

## Error Class Hierarchy

```
ADK::Error (base)
├── ADK::ToolError           # Tool execution errors
│   └── ADK::ToolArgumentError  # Invalid tool arguments
├── ADK::PlanningError       # Planner failures
├── ADK::SessionError        # Session management errors
├── ADK::StoreError          # Storage errors
├── ADK::McpError            # MCP protocol errors
│   ├── ADK::McpConnectionError
│   └── ADK::McpProtocolError
├── ADK::StateValidationError
├── ADK::SerializationError
└── ADK::WebhookConfigurationError
```
