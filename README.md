# ADK Ruby

[![Gem Version](https://badge.fury.io/rb/adk-ruby.svg)](https://badge.fury.io/rb/adk-ruby)

**Author:** Taylor Weibley
**Repository:** [https://github.com/tweibley/adk-ruby](https://github.com/tweibley/adk-ruby)

ADK (Agent Development Kit) for Ruby is a framework for building AI agents with dynamic tool selection, multi-step planning, and session management.

## Features

- **Flexible Agent Architecture**: Create agents with custom tools, models, and capabilities
- **Dynamic Tool System**: Register and use tools with automatic parameter validation
- **LLM-Powered Multi-Step Planning**: Agents can break down complex tasks into steps
- **Session Management**: Track and manage agent interactions with persistent sessions
- **Command Line Interface**: Easy-to-use CLI for running agents and web UI
- **Web UI**: Visual interface for agent interaction and monitoring
- **Event-Based Communication**: Structured events for agent responses and errors
- **Comprehensive Logging**: Detailed logging of agent operations and planning
- **Agent Definition**: Define agents with names, descriptions, and specific LLM models
- **Tool Integration**: Equip agents with custom tools (Ruby classes inheriting `ADK::Tool`)
- **Automatic Planning**: Uses a specified LLM (e.g., Gemini) to automatically plan which tools to use based on user input
- **Tool Parameter Injection**: Automatically injects results from previous steps into subsequent tool parameters (using `[Result from step N]` placeholders)
- **Agent Delegation**: Agents can delegate tasks to other agents using the built-in `:delegate_task` tool
- **Metrics**: Basic Prometheus metrics endpoint (`/metrics`) via `prometheus-client`
- **Asynchronous Job Handling**: Support for long-running tasks via background jobs (using Sidekiq). See [Async Jobs with Sidekiq](docs/async_jobs_sidekiq.md)
- **Dynamic Agent Delegation**: Enables agent coordination through direct delegation, allowing complex workflows where agents can transfer control to specialized agents while maintaining session state.
- **Agent Hierarchy**: Organize agents in parent-child relationships, creating sophisticated agent structures.
- **Workflow Agents**: Support for sequential, parallel, and loop agent patterns.
- **Session State Sharing**: Maintain continuity across agent boundaries with shared session state.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'adk-ruby'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install adk-ruby
```

## Dependencies

- Ruby >= 3.0.0
- `concurrent-ruby`
- `redis` (for Redis session service, agent definitions, and Sidekiq)
- `thor` (for CLI)
- `logger`
- `prometheus-client`
- `gemini-ai` (or other LLM client gem if using a different planner)
- `sidekiq` (Required for asynchronous job feature)
- *(Web UI)* `sinatra`, `sinatra-contrib`, `puma`, `slim`, `sass-embedded`
- *(Development)* `rspec`, `rake`, `rubocop`, `yard`, `pry`, `pry-byebug`, `dotenv`, `webmock`

## Configuration

### Environment Variables

- `RACK_ENV`: Set to `development` or `production` (default: `development`)
- `ADK_LOG_LEVEL`: Logging level (default: `DEBUG` in development, `WARN` otherwise, options: `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`, `NONE`).
- `REDIS_URL`: Redis connection URL (default: `redis://localhost:6379/0`). Used for session storage (if using Redis) and Sidekiq.
- `GEMINI_API_KEY`: Your Google API key for the planner (required if using default `ADK::Planner`).
- `HTTP_PROXY`, `HTTPS_PROXY`: Standard proxy variables if needed for LLM API calls.

### Redis Setup

ADK uses Redis for session persistence (optional) and Sidekiq message broking. Ensure Redis is running:

```bash
# macOS (via Homebrew)
brew services start redis

# Linux
sudo service redis-server start

# Docker Compose
docker compose up

# Docker
docker run --name adk-redis -d -v cache:/data docker.io/library/redis:8.0-alpine redis-server --save 60 1 --loglevel warning

```

### Sidekiq Setup

For the asynchronous job feature:
1. Ensure the `sidekiq` gem is installed (`bundle install`).
2. Ensure Redis is running and configured via `REDIS_URL`.
3. Use the ADK CLI to manage Sidekiq workers:
   ```bash
   # Start a Sidekiq worker (uses ADK environment by default)
   bundle exec adk sidekiq start

   # Start with custom options
   bundle exec adk sidekiq start --queue default,critical --concurrency 10 --verbose

   # Check worker status
   bundle exec adk sidekiq status

   # List pending jobs
   bundle exec adk sidekiq list_jobs

   # Stop workers gracefully
   bundle exec adk sidekiq stop
   ```

   For custom worker configurations, you can specify a require path:
   ```bash
   bundle exec adk sidekiq start --require path/to/your/worker.rb
   ```

## Quick Start

1.  **Create a `.env` file:**
   ```
   RACK_ENV=development
   ADK_LOG_LEVEL=DEBUG  # Optional, for detailed logging
   REDIS_URL=redis://localhost:6379/0
   GEMINI_API_KEY=your_gemini_api_key_here
   ```

2.  **(Optional) Run Sidekiq Workers:** If using async tools, start workers using the ADK CLI (see Sidekiq Setup).

3.  **Start the Web UI:**
   ```bash
   bundle exec adk web start
   ```

4.  **Access the Web Interface:**
   Open your browser to `http://localhost:4567`

## Examples

ADK comes with several examples demonstrating different capabilities:

### 1. Simple Echo Agent (`examples/simple_agent.rb`)
A basic example showing session-based agent interaction:
```ruby
require 'adk'
# Ensure tool classes like ADK::Tools::Echo are loaded so they can be found by name.

# Define the agent's properties
echo_agent_definition = ADK::AgentDefinition.new.define do |a|
  a.name :simple_echo_agent # Agent name should be a Symbol
  a.description 'A simple agent that can echo messages'
  a.instruction 'You are an echo agent. Your task is to repeat the user\\'s input exactly.' # Instruction is required
  a.use_tool :echo         # Specify tools by their registered name (Symbol)
end

# Instantiate the agent with the definition
agent = ADK::Agent.new(definition: echo_agent_definition)

# Create session
session_service = ADK::SessionService::InMemory.new
session = session_service.create_session(app_name: agent.name, user_id: 'example_user')

begin
  # Start the agent (connects to MCP if configured, sets state)
  agent.start

  # Run task
  result = agent.run_task(
    session_id: session.id,
    user_input: 'Hello, world!',
    session_service: session_service
  )

  puts "Agent Response: #{result.inspect}"

ensure
  # Stop the agent (disconnects from MCP, sets state)
  agent.stop
end
```

### 2. Random Calculator (`examples/random_calculator.rb`)
Demonstrates multi-step planning with multiple tools:
```ruby
require 'adk'
# Ensure tools like ADK::Tools::RandomNumberTool and ADK::Tools::Calculator are loaded
# and globally registered so they can be found by their names (:random_number, :calculator).

random_calc_definition = ADK::AgentDefinition.new.define do |a|
  a.name :random_calculator_agent
  a.description 'An agent that uses random number and calculator tools.'
  a.instruction 'Generate a random number then perform a calculation with it.' # Basic instruction
  a.use_tool :random_number # Provided by ADK::Tools::RandomNumberTool (assumed registered)
  a.use_tool :calculator    # Provided by ADK::Tools::Calculator (assumed registered)
end

agent = ADK::Agent.new(definition: random_calc_definition)

# Run complex task
result = agent.run_task(
  session_id: session.id,
  user_input: 'Get a random number between 10 and 20, then multiply it by 3.',
  session_service: session_service
)
```

### 3. Multi-Tool Agent (`examples/multi_tool_agent.rb`)
Showcases all available tools and task delegation:
```ruby
require 'adk'
# Ensure all used tools (:echo, :calculator, :cat_facts, :random_number, :delegate_task)
# are loaded and globally registered. For :delegate_task, ADK::Tools::AgentTool provides this.

multi_tool_definition = ADK::AgentDefinition.new.define do |a|
  a.name :multi_tool_agent
  a.description 'An agent that can use multiple tools including echo, calculator, cat facts, random numbers, and task delegation'
  a.instruction 'You are a versatile assistant. Use the appropriate tool for the task.' # Basic instruction
  a.use_tool :echo
  a.use_tool :calculator
  a.use_tool :cat_facts
  a.use_tool :random_number
  a.use_tool :delegate_task # Provided by ADK::Tools::AgentTool
end

agent = ADK::Agent.new(definition: multi_tool_definition)

# Run various tasks
tasks = [
  "Echo this message: Hello from multi-tool agent!",
  "Calculate 15 * 7",
  "Get me a cat fact",
  "Generate a random number between 1 and 10",
  "Delegate this task to calculator_agent: what is 20 / 4"
]
tasks.each do |task|
  result = agent.run_task(
    session_id: session.id,
    user_input: task,
    session_service: session_service
  )
end
```

## Core Concepts

### Agents

Agents are the core components that can:
- Use tools to perform tasks
- Maintain state through sessions
- Plan multi-step operations
- Handle errors gracefully

Agents are initialized by first creating an `ADK::AgentDefinition` and then passing that to `ADK::Agent.new`:

```ruby
require 'adk'

# Assume MyToolClass is defined and globally registered (e.g., provides :my_tool_name)
# ADK::GlobalToolManager.register_tool(MyToolClass) # If not auto-registered

my_agent_definition = ADK::AgentDefinition.new.define do |a|
  a.name :my_agent # Name as a Symbol
  a.description 'Description of what the agent does'
  a.instruction "You are a helpful assistant." # Agent instructions
  a.use_tool :my_tool_name                   # Specify tools by their registered name
  # a.use_tool :another_tool_name
  a.model_name 'gemini-2.0-pro'             # Optional: specify the LLM model
  # Other options: a.temperature, a.fallback_mode, a.mcp_servers, etc.
end

# Instantiate the agent with the definition object
agent = ADK::Agent.new(definition: my_agent_definition)
```

The `ADK::AgentDefinition.new.define` block provides a DSL to set various properties.
The older `ADK::Agent.define` method (which created, saved, and registered a definition) should no longer be used for direct agent instantiation.

### Tools

Tools are modular components that agents can use. Tools inherit from `ADK::Tool`.
Define tool metadata using the simple class-level DSL:

```ruby
require 'adk/tool'

class MyCustomTool < ADK::Tool
  # Description (required)
  tool_description 'Performs a custom action with input.'

  # Optional: Explicitly set the name if inference isn't desired
  # self.explicit_tool_name = :my_tool # Defaults to :my_custom_tool otherwise

  # Define parameters (optional)
  parameter :input_data,
            type: :string,
            description: 'The data needed for the action',
            required: true

  parameter :optional_flag,
            type: :boolean,
            description: 'An optional flag',
            required: false

  # Implement the execution logic
  private def perform_execution(params, context)
    input = params[:input_data]
    flag = params[:optional_flag] # Will be nil if not provided
    # ... do work ...
    { status: :success, result: "Action performed on #{input}" }
  end
end
```

**Built-in Tools:**
- **Echo**: Simple message echoing (`:echo`)
- **Calculator**: Basic arithmetic operations (`:calculator`)
- **CatFacts**: Retrieve random cat facts (`:cat_facts`)
- **RandomNumber**: Generate random numbers (`:random_number`)
- **AgentTool**: Delegate tasks to other agents (`:delegate_task`)
- **BaseAsyncJobTool**: Base class for tools starting background jobs via Sidekiq.
- **CheckJobStatusTool**: Built-in tool to check the status/result of a Sidekiq job started by an `BaseAsyncJobTool` (`:check_job_status`).

**Adding Tools to Agents:**

Tools are made available to an agent by listing their registered names (symbols) in the agent's definition using `a.use_tool :tool_name`. The tool classes themselves must be loaded and registered with the `ADK::GlobalToolManager` beforehand (e.g., by requiring their source files if they self-register, or by explicit `ADK::GlobalToolManager.register_tool(ToolClass)` calls).

```ruby
# 1. Define an agent that uses specific tools by name:
# Ensure MyCustomTool (providing :my_custom_tool) and ADK::Tools::Calculator (providing :calculator)
# are loaded and globally registered.
# ADK::GlobalToolManager.register_tool(MyCustomTool) # If needed

agent_definition_with_tools = ADK::AgentDefinition.new.define do |a|
  a.name :agent_using_tools
  a.description 'This agent uses a custom tool and the calculator.'
  a.instruction 'Perform tasks using my custom tool or the calculator.'
  a.use_tool :my_custom_tool
  a.use_tool :calculator
end

agent = ADK::Agent.new(definition: agent_definition_with_tools)

# The old methods of adding tools during ADK::Agent.new (like :tool_classes, :tool_paths)
# or in an ADK::Agent.define block (like :discover_tools_in, :add_tool_classes) are deprecated
# in favor of defining tools by name in the ADK::AgentDefinition.
```

**Tool Implementation Notes:**
- Define metadata using the `tool_description` and `parameter` class methods (or `self.explicit_tool_name = ...`).
- The old `define_metadata` method is **deprecated** but still functional for backward compatibility.
- Implement the core logic in the `perform_execution(params, context)` method.
- Return `{ status: :success, result: ... }` on success.
- Return `{ status: :pending, job_id: ... }` for asynchronous jobs started via `BaseAsyncJobTool`.
- **For errors, `raise ADK::ToolArgumentError, "message"` for invalid parameters or `raise ADK::ToolError, "message"` for other execution failures.** The agent will catch these and record an appropriate error event.

### Sessions

Sessions track agent interactions and maintain state:
```ruby
session_service = ADK::SessionService::InMemory.new
session = session_service.create_session(
  app_name: agent.name,
  user_id: 'user123'
)
```

### Events

Events provide structured communication:
```ruby
# Success event
ADK::Event.new(
  role: :agent,
  content: { status: :success, result: 'Task completed' }
)

# Error event
ADK::Event.new(
  role: :agent,
  content: { status: :error, error_message: 'Something went wrong' }
)

# Pending event (for async jobs)
ADK::Event.new(
  role: :agent,
  content: { status: :pending, job_id: 'jid_abc123', message: 'Job enqueued.' }
)
```

## Development

After checking out the repo:

1. **Install Dependencies:**
   ```bash
   bundle install
   ```

2. **Setup Environment:**
   - Ensure Redis is running
   - Create a `.env` file with required variables (see Configuration)
   - Set `ADK_LOG_LEVEL=DEBUG` for detailed logging

3. **Run Tests:**
   ```bash
   bundle exec rake spec     # Run RSpec tests
   bundle exec rake rubocop  # Run Rubocop linting
   bundle exec rake yard     # Generate YARD documentation
   ```

4. **Run Examples:**
   ```bash
   bundle exec ruby examples/simple_agent.rb
   bundle exec ruby examples/random_calculator.rb
   bundle exec ruby examples/multi_tool_agent.rb
   ```

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/tweibley/adk-ruby](https://github.com/tweibley/adk-ruby).

## License

If you are DHH or work at Basecamp/37signals you absolutely cannot use this.

## Asynchronous Jobs with Sidekiq

ADK supports offloading long-running tasks to Sidekiq background jobs, preventing the agent from blocking.

*   Implement tasks as Sidekiq Workers.
*   Create an ADK Tool inheriting from `ADK::Tools::BaseAsyncJobTool` to enqueue the job.
*   Use the built-in `:check_job_status` tool to poll for results using the `job_id` returned by the starting tool.
*   Requires a running Redis instance and a separate Sidekiq worker process for your jobs.

See the detailed documentation: [docs/async_jobs_sidekiq.md](docs/async_jobs_sidekiq.md)

## Creating Custom Tools

(Existing content about creating tools...)

### Making HTTP Requests in Tools

If your custom tool needs to make HTTP requests to external APIs, you can leverage the built-in `ADK::Tools::Base::HttpClient` mixin. This provides a standardized way to make requests using the `excon` gem, handling common concerns like default headers, timeouts, logging, JSON encoding, and error wrapping.

**1. Include the Module:**

```ruby
require_relative '../tool'
require_relative 'base/http_client'

class MyApiTool < ADK::Tool
  include ADK::Tools::Base::HttpClient

  # ... tool metadata ...

  API_BASE_URL = 'https://api.my_service.com/v2/'

  def initialize(**options)
    super(**options)
    # Setup the client in initialize
    setup_http_client(
      base_url: API_BASE_URL,
      headers: { 'Accept' => 'application/vnd.api+json' },
      options: { read_timeout: 10, connect_timeout: 3 }
    )
  end

  private

  def perform_execution(params, context)
    # ... use helper methods ...
  end
end
```

**2. Setup the Client:**

Call `setup_http_client` within your tool's `initialize` method. Key arguments:

*   `base_url:` (String, Required): The base URL for the API your tool interacts with.
*   `headers:` (Hash, Optional): Default headers to send with every request (e.g., `Accept`, `Content-Type`). A default `User-Agent` is automatically added.
*   `options:` (Hash, Optional): Options passed directly to `Excon.new`. Use this to configure timeouts (`:read_timeout`, `:write_timeout`, `:connect_timeout`), persistence (`:persistent`, default: `true`), proxy settings (`:proxy`), SSL verification (`:ssl_verify_peer`), etc.

**3. Use Request Helpers:**

The module provides public helper methods for common HTTP verbs:

*   `http_get(path, query: {}, headers: {}, options: {})`
*   `http_post(path, body: nil, query: {}, headers: {}, options: {})`
*   `http_put(path, body: nil, query: {}, headers: {}, options: {})`
*   `http_delete(path, query: {}, headers: {}, options: {})`

These methods handle joining the `path` with the `base_url`, merging default/per-request headers and options, and automatic JSON encoding for `Hash` bodies in POST/PUT requests.

```ruby
# Inside perform_execution
def perform_execution(params, context)
  # Simple GET request
  resource_id = params[:id]
  response = http_get("items/#{resource_id}", query: { fields: 'name,value' })
  data = JSON.parse(response.body)

  # POST with Hash payload (auto-JSON encoded)
  create_payload = { name: params[:name], value: params[:value] }
  # Override read timeout for this specific request
  post_response = http_post("items", body: create_payload, options: { read_timeout: 5 })

  # POST with string payload (e.g., XML) and custom headers
  xml_payload = "<data><name>#{params[:name]}</name></data>"
  xml_headers = { 'Content-Type' => 'application/xml', 'X-API-Key' => context.get_credential(:api_key) }
  xml_response = http_post("items/import", body: xml_payload, headers: xml_headers)

  # Return combined result (example)
  { status: :success, result: { created_id: JSON.parse(post_response.body)['id'], import_status: xml_response.status } }
rescue ADK::ToolError => e
  # Handle specific errors from HttpClient
  ADK.logger.error "API Tool Error: #{e.message}"
  if e.is_a?(ADK::ToolHttpError) && e.response&.status == 401
    # Potentially trigger re-authentication or specific handling
    return { status: :error, error_message: "Authentication failed: #{e.message}" }
  end
  # Re-raise or return generic error
  { status: :error, error_message: e.message }
end
```

**4. Authentication:**

The `HttpClient` module does *not* manage authentication state itself. Your tool is responsible for retrieving credentials (e.g., from its configuration or the `ToolContext`) and injecting them into the `headers:` parameter for each request helper call.

```ruby
# Example using context for a Bearer token
auth_token = context.get_credential(:bearer_token)
response = http_get("/protected", headers: { 'Authorization' => "Bearer #{auth_token}" })

# Example using context for an API key
api_key = context.get_credential(:api_key)
response = http_post("/data", body: {..}, headers: { 'X-Api-Key' => api_key })
```

**5. Error Handling:**

The request helpers automatically rescue common `Excon::Error` subclasses and re-raise them as standardized `ADK::ToolError` subclasses:

*   `ADK::ToolTimeoutError` (for timeouts)
*   `ADK::ToolNetworkError` (for socket/connection issues)
*   `ADK::ToolCertificateError` (for SSL cert issues, inherits from `ToolNetworkError`)
*   `ADK::ToolHttpError` (for 4xx/5xx responses). Includes the `Excon::Response` object in the `response` attribute.
*   `ADK::ToolError` (for other Excon errors or internal issues like JSON parsing failure).

Your tool should typically rescue `ADK::ToolError` (or specific subclasses) in its `perform_execution` method to handle these failures gracefully.

## Web UI

The ADK includes a web interface (built with Sinatra and HTMX) for managing agent definitions, viewing sessions, and interacting with agents.

To start the web UI:

```bash
bundle exec adk web start
```

## Inbound Webhooks (New!)

The ADK now supports triggering agent tasks via incoming HTTP webhooks. This allows external systems (like Git repositories, CI/CD pipelines, monitoring tools, or other applications) to initiate agent workflows asynchronously.

Key features include:

*   **Dynamic Agent Routing:** Trigger specific agents using a configurable URL pattern (e.g., `POST /webhooks/agents/your_agent_name/trigger`).
*   **Agent-Defined Configuration:** Webhook behavior (validation, payload transformation, session mapping) is configured directly within the agent's definition metadata.
*   **Asynchronous Processing:** Webhooks are quickly acknowledged (`202 Accepted`), and the corresponding agent task is queued for background processing using Sidekiq.
*   **Security:** Supports request validation using shared secrets (e.g., HMAC) or custom logic.

For detailed configuration and usage, please refer to the [Webhook Implementation Plan](docs/inbound-webhook-to-agent.md).
