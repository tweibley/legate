# ADK Ruby

Agent Development Kit (ADK) for Ruby is a framework for building and managing AI agents. It provides a foundation for creating intelligent agents that can perform tasks, maintain state, interact with tools, and utilize language models for planning.

## Features

*   Flexible agent architecture (`ADK::Agent`).
*   Dynamic Tool System with self-registration (`ADK::Tool`, `ADK::ToolRegistry`).
*   Included Tools:
    *   `Echo`: Echoes messages with a random cat fact.
    *   `Calculator`: Performs basic arithmetic.
*   LLM-powered Planning: Uses Google Gemini (via `gemini-ai` gem) to select tools based on task descriptions (`ADK::Planner`).
*   Basic Memory Management (`ADK::Memory` - short-term & long-term placeholders).
*   Session Management (`ADK::Session` - placeholder).
*   **Redis Persistence:** Agent definitions (name, description, configured tools) are stored in Redis.
*   **Web Interface:** (Sinatra/Slim/HTMX) for managing and interacting with agents:
    *   View defined agents (from Redis) and their running status.
    *   Create new agent definitions with tool selection (saved to Redis).
    *   Start/Stop agents (manages runtime instances).
    *   Chat interactively with *running* agents.
    *   Execute tasks directly via JSON input for *running* agents.
    *   View available tools (from Tool Registry).
    *   Execute tools directly via a form.
*   **Command Line Interface:** Basic commands for tools and web server control. (Note: Agent CLI commands currently do not interact with persistence).
*   Standard Ruby tooling: Bundler, Rake, RSpec, Rubocop, Yard.

## Installation

### Prerequisites

*   Ruby (>= 2.7.0 recommended, check `.mise.toml` for current version).
*   Bundler (`gem install bundler`).
*   Redis Server (running locally on default port 6379, or configure connection in `lib/adk/web/app.rb`).
*   Google API Key for Gemini (see Configuration section).

### Steps

1.  Add this line to your application's Gemfile:
    ```ruby
    gem 'adk-ruby'
    # Or, if developing locally:
    # gem 'adk-ruby', path: '.'
    ```

2.  Execute:
    ```bash
    bundle install
    ```

3.  (Optional but Recommended for Dev) Create a `.env` file in the project root for development secrets (see Configuration).

Or install it yourself as a system gem (less common for development):

```bash
gem install adk-ruby
```

## Configuration

### Google API Key (for Gemini Planner)

The planner requires a Google API key for the Gemini models.

1.  Obtain an API key from [Google AI Studio](https://aistudio.google.com/).
2.  Provide the key to the application via the environment variable `GOOGLE_API_KEY`.

    *   **Development:** Create a `.env` file in the project root:
        ```dotenv
        # .env
        RACK_ENV=development
        GOOGLE_API_KEY="YOUR_API_KEY_HERE"
        ```
        Ensure the `dotenv` gem is in your Gemfile's development group (`bundle install`). The web app (`lib/adk/web/app.rb`) will load this automatically when `RACK_ENV` is `development`.
        > **Important:** Add `.env` to your `.gitignore` file!

    *   **Production/Other:** Set the `GOOGLE_API_KEY` environment variable directly in your deployment environment *before* running the application.

### Redis Connection

*   By default, the application attempts to connect to Redis at `localhost:6379` without a password.
*   To use a different host, port, password, or database, modify the `Redis.new` call within the `initialize` method of `lib/adk/web/app.rb`. Consider using environment variables (e.g., `ENV['REDIS_URL']`) for production configurations.

## Usage

### Web Interface (Recommended)

This is the primary way to interact with the full feature set.

1.  **Start the server:**
    ```bash
    # Ensure GOOGLE_API_KEY is set in your environment or .env
    # Ensure Redis server is running
    adk web start
    ```
2.  **Access:** Open your browser to `http://localhost:4567` (or the host/port specified).

#### Web UI Features

*   **Agents Page (`/agents`):**
    *   Lists all agent definitions from Redis.
    *   Shows running status (based on current server process).
    *   Displays configured tools for each agent.
    *   Allows creating new agent definitions with tool selection.
*   **Agent Detail Page (`/agents/:name`):**
    *   Shows agent status (Running/Stopped).
    *   Provides Start/Stop buttons (affects runtime state).
    *   Allows interactive chat *only if* the agent is running.
    *   Allows direct task execution (via JSON input) *only if* the agent is running.
    *   Displays the tools configured for the agent definition in Redis.
*   **Tools Page (`/tools`):**
    *   Lists all tools discovered by the `ToolRegistry`.
*   **Tool Detail Page (`/tools/:name`):**
    *   Shows tool description and parameters.
    *   Allows direct execution of the tool via a form (independent of agents).

### Ruby API

Example of basic programmatic usage:

```ruby
#!/usr/bin/env ruby

require 'bundler/setup'
# Ensure environment variables (like API key) are loaded if needed
# require 'dotenv/load' if File.exist?('.env')

require 'adk' # Loads core, registry, and tools

# --- Agent Definition (Values you'd normally load from Redis) ---
agent_name = 'api_agent_001'
agent_description = 'Agent created via API'
agent_tool_names = [:echo, :calculator] # List of tool names this agent should use

# --- Runtime ---

# Create a new agent instance
agent = ADK::Agent.new(
  name: agent_name,
  description: agent_description
)

# Add specific tools based on definition using the registry
puts "Adding tools: #{agent_tool_names}"
agent_tool_names.each do |tool_name|
  tool_instance = ADK::ToolRegistry.create_instance(tool_name)
  if tool_instance
    agent.add_tool(tool_instance)
    puts "- Added #{tool_name}"
  else
    puts "Warning: Tool '#{tool_name}' not found in registry."
  end
end

# Start the agent process/thread (in a real app, manage this properly)
agent.start
puts "Agent '#{agent.name}' started. Running: #{agent.running?}"
puts "Agent tools loaded: #{agent.tools.map(&:name)}"

# Execute tasks using the planner
task1 = 'Say hello and tell me about cats'
puts "\nRunning task 1: '#{task1}'"
result1 = agent.run_task(task1)
puts "Result 1: #{result1}"

task2 = 'what is 12 * 5?'
puts "\nRunning task 2: '#{task2}'"
result2 = agent.run_task(task2)
puts "Result 2: #{result2}"

# Stop the agent
agent.stop
puts "\nAgent '#{agent.name}' stopped. Running: #{agent.running?}"
```

### Command Line Interface

Provides basic commands.

```bash
# View ADK version
adk version

# --- Tool Commands (Uses Tool Registry) ---
adk tool list
adk tool info echo
adk tool info calculator
adk tool execute echo Hello there
adk tool execute calculator 10 5 multiply # Note: Arg parsing is basic

# --- Agent Commands (CAVEAT) ---
# These commands currently create *temporary, non-persisted* agent instances.
# They DO NOT interact with the Redis store or the running agents managed by the web UI.
# Use the Web Interface for persistent agent management.
adk agent create temp_agent --description="Temporary agent"
# adk agent list # Currently does not list persisted agents
# adk agent start temp_agent # Starts a temporary instance only
# adk agent execute temp_agent "Hello" # Executes on temporary instance only
# adk agent stop temp_agent # Stops temporary instance only

# --- Web Server ---
adk web start --port=5000 # Start web UI on different port

# --- Utility ---
adk compile-sass # Manually compile Sass
```

## Core Concepts

*   **Agent (`ADK::Agent`):** The central entity that manages runtime state, tools, planning, and execution.
*   **Tool (`ADK::Tool`):** Represents a capability the agent can use (e.g., `Echo`, `Calculator`). Tools define metadata (`name`, `description`, `parameters`) using the `define_metadata` class method.
*   **Tool Registry (`ADK::ToolRegistry`):** A singleton module that automatically discovers and registers available `Tool` classes when they are loaded. Used by the UI, CLI, and Agent start process.
*   **Planner (`ADK::Planner`):** Responsible for taking a high-level task and creating an execution plan (currently a single tool invocation). Uses Google Gemini (via `gemini-ai` gem) and requires a `GOOGLE_API_KEY`. Receives the list of tools available to the *specific running agent instance*.
*   **Redis Persistence**: Agent definitions (name, description, list of configured tool names) are stored permanently in Redis Hashes and a central Set. This data survives server restarts.
*   **Runtime State**: The set of *actively running* agent instances is managed in an in-memory hash within the Web UI process (`ADK::Web::App`). This state (including which agents are started/stopped) is lost when the web server restarts.

## Development

After checking out the repo:

1.  **Install Dependencies:**
    ```bash
    bundle install
    ```
2.  **Setup Environment:**
    *   Ensure Redis is running.
    *   Create a `.env` file with `RACK_ENV=development` and your `GOOGLE_API_KEY`.
3.  **Run Web UI:**
    ```bash
    adk web start
    ```
4.  **(Optional) Run Checks/Tasks:** Use Bundler to execute Rake tasks:
    ```bash
    bundle exec rake setup    # Runs spec, rubocop, yard
    bundle exec rake spec     # Run RSpec tests
    bundle exec rake rubocop  # Run Rubocop linting
    bundle exec rake yard     # Generate YARD documentation
    bundle exec rake sass     # Compile Sass manually
    ```

### Sass Compilation

The web UI uses Sass (`.scss` files in `lib/adk/web/public/styles`). These are compiled to `.css` files in `lib/adk/web/public/css`. Compilation happens automatically when the web server starts via `adk web start`, but can also be triggered manually:

```bash
bundle exec rake sass
# or
bin/compile-sass
```

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/yourusername/adk-ruby](https://github.com/yourusername/adk-ruby). (Replace with your actual project URL).

## License

If you are DHH or work at Basecamp/37signals you absolutely cannot use this.