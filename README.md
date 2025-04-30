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
A basic example showing session-based agent interaction using `ADK::Agent.define`:
```ruby
require 'adk'
require 'adk/tools/echo' # Make sure the built-in tool class is loaded

agent = ADK::Agent.define do |a|
  a.name = 'simple_echo_agent'
  a.description = 'A simple agent that can echo messages'
  # Explicitly add the built-in Echo tool class
  a.add_tool_classes ADK::Tools::Echo
  # No need for discover_tools_in for just this built-in tool
end

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
# Assuming calculator and random_number tools are in ./tools
agent = ADK::Agent.new(
  name: 'multi_step_hash_agent_001',
  description: 'An agent that uses multiple tools and returns structured results.',
  tool_paths: './tools' # Load tools from the ./tools directory
)
# Manual addition no longer needed:
# agent.add_tool(ADK::ToolRegistry.create_instance(:random_number))
# agent.add_tool(ADK::ToolRegistry.create_instance(:calculator))

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
# Assuming all standard tools are defined in ./tools or loaded by default
agent = ADK::Agent.new(
  name: 'multi_tool_agent',
  description: 'An agent that can use multiple tools including echo, calculator, cat facts, random numbers, and task delegation',
  tool_paths: './tools' # Discover tools here
)

# Manual addition no longer needed if tools are discoverable:
# tools = [
#   :echo, :calculator, :cat_facts, :random_number, :delegate_task
# ].map { |tool| ADK::ToolRegistry.create_instance(tool) }
# tools.each { |tool| agent.add_tool(tool) }

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

Agents can be initialized directly using `ADK::Agent.new`:

```ruby
agent = ADK::Agent.new(
  name: 'my_agent',
  description: 'Description of what the agent does',
  tool_classes: [MyToolClass], # Explicitly list tool classes
  tool_paths: 'path/to/my/tools', # Or discover tools in a directory
  model_name: 'gemini-2.0-pro' # Optional: specify the LLM model
)
```

Alternatively, use the `ADK::Agent.define` block for a more structured setup:

```ruby
require 'adk'

# Assuming MyToolClass and AnotherToolClass are defined
agent = ADK::Agent.define do |a|
  a.name = 'defined_agent'
  a.description = 'An agent configured using the define block.'
  a.model_name = 'gemini-1.5-flash'

  # Discover tools in directories
  a.discover_tools_in 'path/to/tools', 'path/to/more_tools'

  # Add specific tool classes
  a.add_tool_classes MyToolClass, AnotherToolClass

  # Specify which discovered/added tools the agent should actually *use*
  # If omitted, the agent uses all discovered/added tools.
  a.selected_tool_names = [:my_tool, :another_tool]

  # Configure MCP connection (if needed)
  # a.mcp_servers = ['host1:port1', 'host2:port2']

  # Set fallback mode (optional)
  # a.fallback_mode = :delegate_to_planner
end
```

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
```ruby
# 1. Automatic discovery during agent initialization via tool_paths (using new):
agent_new = ADK::Agent.new(
  name: 'my_agent',
  description: 'Agent with discovered tools',
  tool_paths: './tools' # Loads *.rb files defining ADK::Tool subclasses
)

# 2. Automatic discovery using the define block:
agent_define_discover = ADK::Agent.define do |a|
  a.name = 'my_agent'
  a.discover_tools_in './tools'
end

# 3. Add tool classes explicitly (using new):
agent_new_explicit = ADK::Agent.new(
  name: 'my_agent',
  description: 'Agent with explicit tools',
  tool_classes: [MyCustomTool, ADK::Tools::Calculator]
)

# 4. Add tool classes explicitly using the define block:
agent_define_explicit = ADK::Agent.define do |a|
  a.name = 'my_agent'
  a.add_tool_classes MyCustomTool, ADK::Tools::Calculator
end

# 5. Combine discovery and explicit classes using the define block:
agent_define_mixed = ADK::Agent.define do |a|
  a.name = 'my_mixed_agent'
  a.discover_tools_in './tools'
  a.add_tool_classes AnotherSpecificTool
end

# Manual instance addition (less common, generally use classes/discovery):
# tool_instance = MyCustomTool.new
# agent.add_tool(tool_instance) # This method still exists but isn't the primary way
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
