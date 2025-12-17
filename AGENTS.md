# ADK-Ruby Agent Orientation Guide

> This document provides an orientation for AI agents working with the ADK-Ruby codebase. It covers architecture, key concepts, common patterns, and navigation tips.

## Project Overview

**ADK (Agent Development Kit) for Ruby** is a framework for building AI agents with:
- Dynamic tool selection and execution
- LLM-powered multi-step planning (Gemini)
- Session management and state persistence
- Model Context Protocol (MCP) integration
- Web UI for agent management and interaction
- Authentication system for external API access
- Background job processing via Sidekiq

**Version:** 0.6.7
**Ruby Requirement:** >= 3.0.0  
**Author:** Taylor Weibley

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

## Directory Structure

```
lib/adk/
├── agent.rb              # Core Agent class + AgentDefinition DSL
├── agents.rb             # Entry point for agents module
├── agents/               # Workflow agents
│   ├── sequential_agent.rb
│   ├── parallel_agent.rb
│   └── loop_agent.rb
├── auth.rb               # Entry point for auth module
├── auth/                 # Authentication system
│   ├── scheme.rb         # Base auth scheme
│   ├── schemes/          # API Key, Bearer, OAuth2, OIDC, etc.
│   ├── credential.rb
│   ├── coordinator.rb    # Auth flow coordination
│   ├── token_manager.rb
│   ├── token_store.rb
│   └── excon_middleware.rb  # HTTP middleware for auth
├── callbacks/            # Agent/tool/model callbacks
│   └── callback_context.rb
├── cli.rb                # Entry point for CLI module
├── cli/                  # Thor CLI commands
│   ├── agent_commands.rb
│   ├── auth_commands.rb  # Authentication management
│   ├── deployment_commands.rb
│   ├── session_commands.rb
│   ├── sidekiq_commands.rb
│   ├── skaffold_commands.rb
│   ├── tool_commands.rb
│   └── web_commands.rb
├── generators.rb         # Entry point for generators module
├── generators/           # AI-powered code generators
│   ├── agent_generator.rb  # Generate agent definitions via LLM
│   └── tool_generator.rb   # Generate tool classes via LLM
├── configuration.rb      # ADK.config singleton
├── configuration/        # Configuration submodules
│   └── webhooks.rb
├── definition_store.rb   # Entry point for definition store
├── definition_store/     # Agent definition persistence
│   └── redis_store.rb
├── global_definition_registry.rb  # Global registry for agent definitions (critical for workflows)
├── global_tool_manager.rb # Global tool registration
├── mcp.rb                # Entry point for MCP module
├── mcp/                  # Model Context Protocol
│   ├── client.rb         # MCP client (stdio/sse connections)
│   ├── connection/       # Connection types (stdio, sse)
│   ├── server/           # ADK as MCP server adapters
│   │   ├── adk_agent_adapter.rb
│   │   ├── adk_direct_agent_adapter.rb
│   │   └── adk_tool_adapter.rb
│   └── tool_wrapper.rb   # Wrap MCP tools as ADK tools
├── planner.rb            # LLM-powered planning (Gemini)
├── session.rb            # Session object (events, state)
├── session_service/      # Session persistence
│   ├── base.rb
│   ├── in_memory.rb
│   └── redis.rb
├── tool.rb               # Base Tool class
├── tool/
│   ├── error.rb
│   └── metadata_dsl.rb   # Tool definition DSL
├── tool_context.rb       # Context passed to tools
├── tool_registry.rb      # Per-agent tool registry
├── tools/                # Built-in tools
│   ├── echo.rb
│   ├── calculator.rb
│   ├── random_number_tool.rb
│   ├── cat_facts.rb
│   ├── agent_tool.rb     # Delegate to other agents
│   ├── base_async_job_tool.rb  # Base for async Sidekiq tools
│   ├── check_job_status_tool.rb
│   └── base/
│       └── http_client.rb
├── web/                  # Web UI
│   ├── app.rb            # Sinatra application
│   ├── routes/           # Route modules
│   ├── views/            # Slim templates
│   └── webhook_listener.rb  # Inbound webhook handler
├── webhook_job_worker.rb # Sidekiq worker for webhook processing
└── errors.rb             # Error class hierarchy
```

---

## Core Concepts

### 1. AgentDefinition

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

**Key attributes:**
- `name` (Symbol) - unique identifier
- `instruction` (String) - system prompt for LLM
- `tool_names` (Set<Symbol>) - tools this agent can use
- `model_name` (String) - Gemini model to use
- `agent_type` (Symbol) - `:llm`, `:sequential`, `:parallel`, `:loop`

### 2. Agent

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

**Important methods:**
- `run_task(session_id:, user_input:, session_service:)` - Main entry point
- `available_tools_metadata` - Get tool info for planning
- `add_tool(tool_instance)` - Add tool at runtime
- `find_sub_agent(name)` - Find child agent for workflows

### 3. Tool

Base class for tools that agents can use:

```ruby
class MyTool < ADK::Tool
  # DSL for metadata (preferred)
  tool_description 'What this tool does'
  
  parameter :input,
    type: :string,
    description: 'Input parameter',
    required: true
  
  parameter :optional_flag,
    type: :boolean,
    required: false
  
  private
  
  def perform_execution(params, context)
    # params - validated input parameters (Hash with symbol keys)
    # context - ADK::ToolContext with session info, state access
    
    input = params[:input]
    
    # Success response
    { status: :success, result: "Processed: #{input}" }
    
    # Or raise errors
    # raise ADK::ToolArgumentError, "Invalid input"
    # raise ADK::ToolError, "Execution failed"
  end
end

# Register globally
ADK::GlobalToolManager.register_tool(MyTool)
```

**Built-in tools:**
- `:echo` - Echo messages back
- `:calculator` - Basic math
- `:cat_facts` - Random cat facts (example HTTP tool)
- `:random_number` - Generate random numbers
- `:delegate_task` - Delegate to another agent
- `:check_job_status` - Check async job status

### 4. ToolContext

Context passed to tools during execution:

```ruby
def perform_execution(params, context)
  # Read session state
  value = context.state_get(:my_key)
  
  # Write to pending state (applied after execution)
  context.state_set(:result_key, "some value")
  
  # Access session info
  context.session_id
  context.user_id
  context.app_name
  context.invocation_id
  
  # Authentication helpers
  context.get_token(scheme, credential)
  context.handle_request_auth(request)
end
```

### 5. Session & Events

Sessions track conversation history and state:

```ruby
session_service = ADK::SessionService::InMemory.new  # or Redis.new
session = session_service.create_session(
  app_name: agent.name,
  user_id: 'user123'
)

# Events are immutable records
event = ADK::Event.new(
  role: :user,        # :user, :agent, :tool_request, :tool_result
  content: "Hello",
  tool_name: nil,     # For tool events
  state_delta: {}     # State changes
)

session.add_event(event)
session.get_state(:key)
session.set_state(:key, value)
```

### 6. Planner

The Planner uses Gemini LLM to create multi-step plans:

```ruby
# Internal to Agent - creates JSON plan like:
{
  "thought_process": "User wants to calculate...",
  "plan": [
    {
      "step": 1,
      "type": "tool_use",
      "tool_name": "calculator",
      "tool_input": { "expression": "2 + 2" },
      "reason": "Perform the calculation"
    }
  ]
}
```

### 7. MCP Integration

ADK can act as MCP client or server:

**As Client (consume external tools):**
```ruby
definition = ADK::AgentDefinition.new.define do |a|
  a.name :mcp_agent
  a.instruction 'Use external tools'
  a.mcp_servers [
    { type: :stdio, command: 'npx', args: ['-y', '@some/mcp-server'] }
  ]
end
```

**As Server (expose agents as MCP tools):**

ADK agents and tools can be exposed via MCP using two transport methods:

1. **Stdio** (local MCP, default) - For running alongside local MCP hosts:
```ruby
# Use ADK::Mcp::Server::AdkAgentAdapter or AdkToolAdapter
# See: mcp_server_adk_agent.rb, mcp_server_adk_tool.rb
```

2. **HTTP/Rack** (remote deployment) - For serving over HTTP with SSE:
```ruby
# Wrap an ADK tool for MCP
AdaptedCalculator = ADK::Mcp::Server::AdkToolAdapter.wrap(ADK::Tools::Calculator)

# Create Rack middleware with fast-mcp
mcp_middleware = FastMcp.rack_middleware(
  base_app,
  name: 'adk-rack-server',
  version: '1.0.0'
) do |server|
  server.register_tool(AdaptedCalculator)
end

# Run with Puma (exposes /mcp/sse and /mcp/messages endpoints)
Rack::Handler::Puma.run mcp_middleware, Port: 9292
```

See `examples/mcp_server_rack.rb` for a complete HTTP/Rack example.

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
8. │→ Store output to session state (if output_key defined)
   │
9. └→ Return final ADK::Event
```

### Tool Registration Flow

```
1. Tool class defined (inherits ADK::Tool)
   │
2. │→ DSL methods set metadata (tool_description, parameter)
   │
3. │→ ADK::GlobalToolManager.register_tool(ToolClass)
   │   └── Stores by symbolic name (e.g., :echo)
   │
4. │→ AgentDefinition uses `a.use_tool :echo`
   │   └── Stores name in tool_names Set
   │
5. │→ Agent instantiation
   │   └── Resolves tool names to instances via GlobalToolManager
   │
6. └→ Tool available for planning and execution
```

---

## Common Patterns

### Creating a New Tool

```ruby
# lib/my_app/tools/weather_tool.rb
require 'adk/tool'
require 'adk/tools/base/http_client'

class WeatherTool < ADK::Tool
  include ADK::Tools::Base::HttpClient
  
  tool_description 'Get current weather for a location'
  
  parameter :location, type: :string, required: true,
    description: 'City name or coordinates'
  
  def initialize(**options)
    super
    setup_http_client(
      base_url: 'https://api.weather.com/v1/',
      headers: { 'Accept' => 'application/json' }
    )
  end
  
  private
  
  def perform_execution(params, context)
    location = params[:location]
    
    # Use auth from context if configured
    api_key = context.state_get('weather:api_key')
    
    response = http_get("current", 
      query: { q: location },
      headers: { 'X-API-Key' => api_key }
    )
    
    data = JSON.parse(response.body)
    { status: :success, result: data['description'] }
  rescue ADK::ToolHttpError => e
    { status: :error, error_message: "API error: #{e.message}" }
  end
end

# Register
ADK::GlobalToolManager.register_tool(WeatherTool)
```

### Creating a Workflow Agent

```ruby
# Sequential workflow
workflow_def = ADK::AgentDefinition.new.define do |a|
  a.name :data_pipeline
  a.instruction 'Process data through multiple stages'
  a.agent_type :sequential
  a.sequential_sub_agent_names [:fetch_agent, :transform_agent, :store_agent]
  a.output_key :pipeline_result
end

# Parallel workflow
parallel_def = ADK::AgentDefinition.new.define do |a|
  a.name :parallel_search
  a.instruction 'Search multiple sources simultaneously'
  a.agent_type :parallel
  a.parallel_sub_agent_names [:google_search, :bing_search, :duckduckgo_search]
end

# Loop workflow
loop_def = ADK::AgentDefinition.new.define do |a|
  a.name :refinement_loop
  a.instruction 'Iteratively refine result'
  a.agent_type :loop
  a.loop_sub_agent_names [:refine_agent, :evaluate_agent]
  a.loop_max_iterations 5
  a.loop_condition_state_key :quality_score
  a.loop_condition_expected_value 'excellent'
end
```

### Using Callbacks

```ruby
definition = ADK::AgentDefinition.new.define do |a|
  a.name :monitored_agent
  a.instruction 'Agent with monitoring'
  a.use_tool :echo
  
  # Track execution time
  a.before_agent_callback do |context|
    context.state_set(:start_time, Time.now.to_f)
    nil # Continue normal execution
  end
  
  a.after_agent_callback do |context, response|
    duration = Time.now.to_f - context.state_get(:start_time)
    puts "Execution took #{duration}s"
    nil # Use response as-is
  end
  
  # Log all tool calls
  a.before_tool_callback do |tool, args, context|
    puts "Calling #{tool.name} with #{args.inspect}"
    nil # Continue
  end
end
```

### Configuring Webhooks

Agents can be triggered by inbound HTTP webhooks:

```ruby
webhook_definition = ADK::AgentDefinition.new.define do |a|
  a.name :webhook_receiver
  a.description 'Receives webhook POSTs and processes messages'
  a.instruction 'Process the incoming webhook message.'
  a.use_tool :echo
  
  # Enable webhook triggering
  a.webhook_enabled true
  
  # Validate incoming requests (e.g., HMAC-SHA256)
  a.webhook_validator :hmac_sha256
  a.webhook_secret ENV['WEBHOOK_SECRET'] || 'your-secret-key'
  
  # Transform the request body into agent input
  a.webhook_transformer ->(request_body) do
    parsed = JSON.parse(request_body)
    "Received message: #{parsed['message']}"
  end
  
  # Extract session ID from payload (or use static)
  a.webhook_session_extractor ->(_request_body) do
    'webhook_session_123'
  end
end

# Register globally so webhook listener can find it
ADK::GlobalDefinitionRegistry.register(webhook_definition)
```

The webhook listener (`ADK::Web::WebhookListener`) handles incoming HTTP requests and routes them to the appropriate agent. See `examples/webhook_receiver_agent.rb`.

### Creating Async Tools with Sidekiq

For long-running tasks, create tools that offload work to Sidekiq background jobs:

```ruby
# 1. Define the Sidekiq Worker
class MyLongRunningWorker
  include Sidekiq::Worker
  
  def perform(task_id, params)
    jid = self.jid  # Get the job ID
    
    # Mark job as started
    ADK::Tools::BaseAsyncJobTool.store_job_pending(jid)
    
    # Do the long-running work...
    result = heavy_computation(params)
    
    # Store the result for later retrieval
    ADK::Tools::BaseAsyncJobTool.store_job_result(jid, result)
  rescue => e
    ADK::Tools::BaseAsyncJobTool.store_job_error(jid, e.message, e.class.name)
    raise
  end
end

# 2. Define the ADK Tool
class MyAsyncTool < ADK::Tools::BaseAsyncJobTool
  tool_description 'Starts a long-running background task'
  
  parameter :task_data, type: :string, required: true,
    description: 'Data to process'
  
  def sidekiq_worker_class
    MyLongRunningWorker
  end
  
  def prepare_job_arguments(params, context)
    [context.session_id, params[:task_data]]
  end
end

# Register the tool
ADK::GlobalToolManager.register_tool(MyAsyncTool)
```

The tool returns `{ status: :pending, job_id: "..." }`. Use the built-in `:check_job_status` tool to poll for results. See `examples/async_job_example.rb` and `examples/workers/sleepy_worker.rb`.

---

## Configuration

### Environment Variables

```bash
RACK_ENV=development|production       # Environment mode
ADK_LOG_LEVEL=DEBUG|INFO|WARN|ERROR  # Logging level
REDIS_URL=redis://localhost:6379/0   # Redis connection
GOOGLE_API_KEY=xxx                   # Gemini API key (alias for GEMINI_API_KEY)
SESSION_SECRET=xxx                   # Web UI session secret
```

### ADK Configuration

```ruby
ADK.configure do |config|
  config.definition_store = ADK::DefinitionStore::RedisStore.new(redis_client: redis)
  config.session_service = ADK::SessionService::Redis.new(redis_options: {})
  config.default_model_name = 'gemini-2.0-flash'
  config.default_temperature = 0.7
end

# Access config
ADK.config.default_model_name
ADK.logger  # Central logger
```

---

## CLI Commands

```bash
# Web UI
bundle exec adk web start                    # Start web server (port 4567)

# Agents
bundle exec adk agent list                   # List defined agents
bundle exec adk agent save <name>            # Save agent definition
bundle exec adk agent delete <name>          # Delete an agent
bundle exec adk agent generate <name>        # Generate agent boilerplate (interactive)
bundle exec adk agent ai-generate            # Generate agent using AI (LLM-powered)
bundle exec adk agent start <name>           # Start agent runtime
  # Options: --quiet/-q, --json
bundle exec adk agent stop <name>            # Stop agent runtime
  # Options: --quiet/-q, --json, --force
bundle exec adk agent status <name>          # Check agent status
  # Options: --json
bundle exec adk agent execute <name> <task>  # Run agent task
  # Options: --session-id=<id>, --user-id=<id>, --redis, --quiet/-q, --json
bundle exec adk agent chat <name>            # Interactive chat with agent
  # Options: --user-id=<id>
bundle exec adk agent export <name>          # Export agent definition

# Tools
bundle exec adk tool list                    # List available tools
bundle exec adk tool info <name>             # Show tool details
bundle exec adk tool execute <name> [args]   # Execute a tool directly
  # Options: --quiet/-q, --json
bundle exec adk tool ai-generate             # Generate tool using AI (LLM-powered)

# Authentication
bundle exec adk auth status                  # Show auth configuration status
bundle exec adk auth scheme list             # List authentication schemes
bundle exec adk auth scheme show <name>      # Show scheme details
bundle exec adk auth scheme create <name>    # Create new auth scheme (interactive)
bundle exec adk auth scheme delete <name>    # Delete an auth scheme
bundle exec adk auth credential list         # List stored credentials
bundle exec adk auth credential show <name>  # Show credential details
bundle exec adk auth credential create <name> # Create new credential (interactive)
bundle exec adk auth credential delete <name> # Delete a credential
bundle exec adk auth credential test <name>  # Test credential validity
bundle exec adk auth mapping list            # List URL-to-scheme mappings
bundle exec adk auth mapping create          # Create new URL mapping (interactive)
bundle exec adk auth mapping delete <index>  # Delete a URL mapping

# Sidekiq (async jobs)
bundle exec adk sidekiq start               # Start worker process
bundle exec adk sidekiq stop                # Stop workers gracefully
bundle exec adk sidekiq status              # Check worker/queue status
bundle exec adk sidekiq list_jobs           # List pending jobs in queue

# Sessions
bundle exec adk session list                # List sessions

# Project Scaffolding
bundle exec adk skaffold <project_name>     # Generate new ADK project structure
```

### AI-Powered Code Generation

ADK includes LLM-powered generators for creating agents and tools from natural language descriptions:

```bash
# Generate an agent interactively
bundle exec adk agent ai-generate
# Prompts for description like: "An agent that monitors GitHub PRs and posts summaries to Slack"

# Generate a tool interactively  
bundle exec adk tool ai-generate
# Prompts for description like: "A tool that fetches weather data from OpenWeatherMap API"
```

The generators use the Gemini LLM (requires `GOOGLE_API_KEY`) to produce well-structured Ruby code that follows ADK conventions. Generated code includes:
- Proper class structure inheriting from `ADK::Agent` or `ADK::Tool`
- DSL-based metadata (descriptions, parameters)
- Appropriate tool selection for agents
- HTTP client integration for API tools

---

## Error Handling

### Error Class Hierarchy

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

### Tool Error Handling

```ruby
def perform_execution(params, context)
  # For invalid parameters
  raise ADK::ToolArgumentError, "Missing required field"
  
  # For execution failures
  raise ADK::ToolError, "External service unavailable"
  
  # The framework catches these and creates appropriate error events
end
```

---

## Testing

```bash
bundle exec rake spec          # Run RSpec tests
bundle exec rake rubocop       # Lint code
bundle exec rake yard          # Generate docs
```

**Test structure:**
```
spec/
├── adk/
│   ├── agent_spec.rb
│   ├── tool_spec.rb
│   ├── planner_spec.rb
│   └── ...
└── spec_helper.rb
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
| Global definitions | `lib/adk/global_definition_registry.rb` |
| Planner | `lib/adk/planner.rb` |
| Sessions | `lib/adk/session.rb` |
| Events | `lib/adk/event.rb` |
| Context | `lib/adk/tool_context.rb` |
| Errors | `lib/adk/errors.rb` |
| MCP Client | `lib/adk/mcp/client.rb` |
| Web App | `lib/adk/web/app.rb` |
| Configuration | `lib/adk/configuration.rb` |
| CLI | `lib/adk/cli.rb` |
| Auth System | `lib/adk/auth.rb` |
| Callbacks | `lib/adk/callbacks/callback_context.rb` |
| Async Job Base | `lib/adk/tools/base_async_job_tool.rb` |
| Webhook Worker | `lib/adk/webhook_job_worker.rb` |

---

## Common Gotchas

1. **Tool names must be Symbols** - Use `:echo` not `'echo'`

2. **AgentDefinition requires instruction** - Always set `a.instruction`

3. **Tools must be registered before use** - Either via `GlobalToolManager.register_tool()` or loaded files that self-register

4. **Agent must be started** - Call `agent.start` before `run_task`

5. **Session state is async** - Use `ToolContext#state_set` which applies after tool execution

6. **MCP connections require agent.start()** - MCP servers connect during agent startup

7. **Workflow agents need sub-agent definitions** - Sub-agents must be registered in GlobalDefinitionRegistry

8. **Event content should be serializable** - Avoid complex objects in event content

9. **Tool perform_execution returns Hash** - Always return `{ status: :success/:error/:pending, ... }`

10. **Planner depends on GOOGLE_API_KEY** - Set this env var for Gemini integration

---

## Examples Directory

The `examples/` directory contains runnable examples organized by category:

### Basics
- `simple_agent.rb` - Minimal agent with echo tool
- `instructed_agent.rb` - Agent with custom instructions
- `multi_tool_agent.rb` - Agent with multiple tools
- `random_calculator.rb` - Calculator and random number tools

### Workflows (Multi-Agent Systems)
- `mas/sequential_workflow.rb` - Run agents in sequence
- `mas/parallel_workflow.rb` - Run agents concurrently
- `mas/loop_workflow.rb` - Iterative refinement loop
- `mas/delegation_example.rb` - Agent-to-agent delegation
- `loop_agent_example.rb` - Loop agent configuration
- `task_refinement_loop_agent.rb` - Self-improving loop

### MCP Integration
**Client (consume external MCP servers):**
- `mcp_client_agent.rb` - Connect to external MCP tools
- `mcp_client_agent_example.rb` - Detailed client example

**Server (expose ADK as MCP server):**
- `mcp_server_adk_agent.rb` - Expose agent via stdio
- `mcp_server_adk_tool.rb` - Expose tool via stdio
- `mcp_server_rack.rb` - **HTTP/Rack** server (SSE transport)
- `mcp_server_async.rb` - Async tool handling
- `mcp_resource_server_example.rb` - MCP resources

### Webhooks & Async Jobs
- `webhook_receiver_agent.rb` - Agent triggered by webhooks
- `webhook-example.rb` - Webhook configuration
- `async_job_example.rb` - Sidekiq background jobs
- `workers/sleepy_worker.rb` - Example Sidekiq worker

### Authentication
- `auth/oauth2_auth.rb` - OAuth2 flow
- `auth/oidc_auth.rb` - OpenID Connect
- `auth/http_bearer_auth.rb` - Bearer token auth
- `auth/service_account.rb` - Service account credentials
- `auth/fiber_auth_example.rb` - Fiber-based auth flows

### Callbacks
- `callback_basics.rb` - Before/after callbacks
- `callback_monitoring.rb` - Monitoring with callbacks

Run examples with: `bundle exec ruby examples/<file>.rb`

---

## Web UI Structure

The Web UI is a Sinatra app using HTMX for dynamic updates:

```
lib/adk/web/
├── app.rb                    # Main application
├── routes/
│   ├── core_routes.rb        # Dashboard, metrics
│   ├── agent_definition_routes.rb  # CRUD agents
│   ├── agent_runtime_routes.rb     # Start/stop agents
│   ├── agent_interaction_routes.rb # Chat interface
│   ├── tools_ui_routes.rb    # Tool management
│   ├── authentication_routes.rb
│   ├── api_routes.rb         # JSON API endpoints
│   └── documentation_routes.rb
├── views/                    # Slim templates
│   ├── layout.slim
│   ├── agents/
│   ├── tools/
│   └── ...
├── webhook_listener.rb       # Inbound webhook handling
└── public/
    └── styles/              # SCSS compiled to CSS
```

Access at `http://localhost:4567` after `bundle exec adk web start`

---

## Task Magic Integration

This project uses a file-based task management system in `.ai/`:

- `.ai/plans/` - PRDs and feature plans
- `.ai/tasks/` - Active task files
- `.ai/TASKS.md` - Master task checklist
- `.ai/memory/` - Archived completed tasks

See `.cursor/rules/.task-magic/` for detailed rules.

---
## For Jules: Our Environment

We use mise to manage our Ruby environment.

1.  **We have ALREADY prepared the environment:**
```bash
#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# 1. System Packages: Check individually before apt update/install
# We gather missing packages first to avoid running apt update unnecessarily
REQUIRED_PKGS="curl libssl-dev libyaml-dev zlib1g-dev libreadline-dev libgdbm-dev"
MISSING_PKGS=""

for pkg in $REQUIRED_PKGS; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
done
if [ -n "$MISSING_PKGS" ]; then
    echo "Installing missing packages: $MISSING_PKGS"
    sudo apt-get update -y
    sudo apt-get install -y $MISSING_PKGS
else
    echo "System packages already installed."
fi

# 2. Install Mise: Check for the binary
if [ ! -f "$HOME/.local/bin/mise" ]; then
    echo "Installing mise..."
    curl https://mise.run | sh
else
    echo "mise already installed."
fi

# Set path for the duration of this script
export PATH="$HOME/.local/bin:$PATH"

# 3. Activate Mise: Always run this to ensure the current shell has access to tools
eval "$(mise activate bash --shims)"

# 4. Mise Tools: 'mise install' is generally smart, but we can skip if you want pure speed.
# However, keep it to ensure version compliance.
mise trust -a
mise install

# 5. Global Gems: Check if they exist
if ! gem list -i bundler >/dev/null 2>&1; then
    gem install --quiet bundler
fi

if ! gem list -i rake >/dev/null 2>&1; then
    gem install --quiet rake
fi

echo "Done with Ruby install!"

# 6. Bundle Install: Use 'bundle check' to skip 'bundle install'
if ! bundle check >/dev/null 2>&1; then
    echo "Installing project dependencies..."
    bundle install
else
    echo "Bundle dependencies satisfied."
fi

echo
echo "Environment prepared!"

if ! dpkg -s valkey >/dev/null 2>&1; then
    sudo apt install -y valkey valkey-redis-compat
    sudo systemctl start valkey-server
    sudo systemctl enable valkey-server
fi
```

2.  **Run Tests:**
    ```bash
    # Execute the test suite inside the container
    bundle exec rspec
    ```

3.  **Environment Variables:**
    `GOOGLE_API_KEY` and `WEBHOOK_RECEIVER_SECRET` should be set in your local environment. 
    
    *Note: `ADK_LOG_LEVEL` defaults to `debug` and `REDIS_URL` is automatically configured to point to the redis service.*
