# ADK Ruby

**Author:** Taylor Weibley
**Repository:** [https://github.com/tweibley/adk-ruby](https://github.com/tweibley/adk-ruby)

Agent Development Kit (ADK) for Ruby is a framework for building and managing AI agents. It provides a foundation for creating intelligent agents that can perform tasks, maintain state, interact with tools, and utilize language models for planning complex, multi-step operations.

## Features

*   **Flexible Agent Architecture (`ADK::Agent`):** Central class managing runtime state, tool execution, and interaction with the planner and memory.
*   **Dynamic Tool System (`ADK::Tool`, `ADK::ToolRegistry`):**
    *   Tools define metadata (`name`, `description`, `parameters`) and are automatically registered upon loading.
    *   **Included Tools:**
        *   `Echo`: Echoes back the provided message.
        *   `Calculator`: Performs basic arithmetic operations.
        *   `CatFacts`: Fetches a random cat fact from an online API.
        *   `RandomNumberTool`: Generates a random integer within an optional range.
    *   **Standardized Hash Results:** Tools return results in a consistent hash format (e.g., `{ status: :success, result: ... }` or `{ status: :error, error_message: ... }`) for better status signaling and LLM interpretability.
*   **LLM-powered Multi-Step Planning (`ADK::Planner`):**
    *   Uses Google Gemini (via `gemini-ai` gem, tested with `gemini-1.5-flash`) to interpret high-level tasks and generate a sequence of tool execution steps.
    *   Handles basic result passing between steps (e.g., output of step 1 used as input for step 2).
*   **Basic Memory & Session Management (`ADK::Memory`, `ADK::Session`):** Placeholder classes for state management within an agent's lifecycle.
*   **Redis Persistence:** Agent **definitions** (name, description, configured tools) are stored in Redis, surviving application restarts.
*   **Web Interface (Sinatra/Slim/HTMX):** A comprehensive UI for:
    *   Managing agent definitions stored in Redis (Create, View, Delete).
    *   Viewing available tools from the Tool Registry.
    *   Starting/Stopping agent **runtime instances** (managed in web server memory).
    *   Interacting with *running* agents via chat (handles multi-step results).
    *   Executing tasks directly via JSON input for *running* agents (displays structured results).
    *   Executing tools directly via a form (displays structured results).
*   **Command Line Interface (Thor):**
    *   Manage agent definitions in Redis (`adk agent list/create/update/delete`).
    *   Execute tasks ephemerally using an agent definition (`adk agent execute <name> "task"`, displays structured results).
    *   Verify agent startup based on definition (`adk agent start <name>`).
    *   List and get info on tools (`adk tool list/info <name>`).
    *   Execute tools directly using `key=value` arguments (`adk tool execute <name> [param=value...]`, displays structured results).
    *   Control the web server (`adk web start`).
*   **Configurable Logging:** Via `ADK_LOG_LEVEL` environment variable (DEBUG, INFO, WARN, ERROR, FATAL, NONE).
*   **Standard Ruby tooling:** Bundler, Rake, RSpec, Rubocop, Yard.

## Installation

### Prerequisites

*   Ruby (>= 2.7.0 recommended, check `.mise.toml` for current version).
*   Bundler (`gem install bundler`).
*   Redis Server (running locally on default port 6379, or configure connection).
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
        # Optional: Set log level (DEBUG, INFO, WARN, ERROR, FATAL, NONE) - Default is WARN
        # ADK_LOG_LEVEL=INFO
        ```
        Ensure the `dotenv` gem is in your Gemfile's development group (`bundle install`). The application loads `.env` automatically.
        > **Important:** Add `.env` to your `.gitignore` file!

    *   **Production/Other:** Set the `GOOGLE_API_KEY` environment variable directly in your deployment environment *before* running the application.

### Redis Connection

*   By default, the application (Web UI and CLI) attempts to connect to Redis at `localhost:6379` without a password.
*   To use a different host, port, password, or database, modify the `Redis.new` calls within `lib/adk/web/app.rb` and `lib/adk/cli/agent_commands.rb`. Consider using environment variables (e.g., `ENV['REDIS_URL']`) for production configurations.

### Logging Verbosity

*   Control the detail level of logs by setting the `ADK_LOG_LEVEL` environment variable (or in `.env`).
*   Valid levels: `DEBUG`, `INFO`, `WARN` (Default), `ERROR`, `FATAL`, `NONE` (or `SILENT`).

## Usage

### Web Interface (Recommended)

This is the primary way to manage agent definitions and interact with running instances.

1.  **Start the server:**
    ```bash
    # Ensure GOOGLE_API_KEY is set in your environment or .env
    # Ensure Redis server is running
    adk web start
    ```
2.  **Access:** Open your browser to `http://localhost:4567` (or the host/port specified).

#### Web UI Features

*   **Agents Page (`/agents`):** Manage Redis definitions (Create, List, Delete), view runtime status, start/stop runtime instances.
*   **Agent Detail Page (`/agents/:name`):** View details, start/stop controls, interactive chat (if running), direct JSON task execution (if running).
*   **Tools Page (`/tools`):** Browse available tools from the Registry.
*   **Tool Detail Page (`/tools/:name`):** View tool parameters, execute directly via a form.

### Ruby API

Example of programmatic usage, showing how to handle the new hash-based results:

```ruby
#!/usr/bin/env ruby

require 'bundler/setup'
# Ensure environment variables (like API key) are loaded if needed
# require 'dotenv/load' if File.exist?('.env')

require 'adk' # Loads core, registry, and tools

# --- Agent Definition (Normally from Redis) ---
agent_name = 'api_agent_001'
agent_description = 'Agent created via API for multi-step task'
agent_tool_names = [:random_number, :calculator] # Tools this agent can use

# --- Runtime ---
agent = ADK::Agent.new(
  name: agent_name,
  description: agent_description
)

# Add specific tools based on definition
puts "Adding tools: #{agent_tool_names.join(', ')}"
agent_tool_names.each do |tool_name|
  tool_instance = ADK::ToolRegistry.create_instance(tool_name)
  if tool_instance then agent.add_tool(tool_instance) else puts "Warn: Tool '#{tool_name}' not found." end
end

agent.start
puts "Agent '#{agent.name}' started. Running: #{agent.running?}"

# Execute a task that requires multiple steps
task = "Generate a random number between 1 and 10, then multiply it by 5."
puts "\nRunning task: '#{task}'"
result_data = agent.run_task(task) # Returns array of hashes for multi-step

puts "Raw result data: #{result_data.inspect}"

# Interpret the result
puts "\nInterpreted Result:"
if result_data.is_a?(Array)
  puts " Status: Multi-Step Plan Executed"
  final_step_result = nil
  result_data.each_with_index do |step_hash, index|
    if step_hash.is_a?(Hash) && step_hash[:status] == :success
      puts "  Step #{index + 1} (Success): #{step_hash[:result]}"
      final_step_result = step_hash[:result] # Store last successful result
    elsif step_hash.is_a?(Hash) && step_hash[:status] == :error
      puts "  Step #{index + 1} (Error): #{step_hash[:error_message]}"
      break # Stop processing steps on error
    else
      puts "  Step #{index + 1} (Unknown Format): #{step_hash.inspect}"
      break
    end
  end
  puts " -> Final usable outcome from plan: #{final_step_result || 'None (due to error or no successful steps)'}"

elsif result_data.is_a?(Hash) # Single step or planning error
  if result_data[:status] == :success
    puts " Status: Single Step Success"
    puts " Result: #{result_data[:result]}"
  else
    puts " Status: Error"
    puts " Message: #{result_data[:error_message]}"
  end
else
  puts " Status: Unknown (Unexpected Format)"
  puts " Raw Data: #{result_data.inspect}"
end

agent.stop
puts "\nAgent '#{agent.name}' stopped."
```

### Command Line Interface

Provides commands for managing agent definitions, tools, and executing tasks ephemerally.

```bash
# View ADK version
adk version

# --- Tool Commands (Uses Tool Registry) ---
adk tool list
adk tool info calculator
# Execute using key=value pairs
adk tool execute calculator operand1=10 operand2=5 operation=add
adk tool execute echo message="Hello from CLI"
adk tool execute random_number min=10 max=20
adk tool execute cat_facts

# --- Agent Definition Commands (Uses Redis) ---
adk agent list
adk agent create <name> --description="<desc>" --tools=echo,random_number
adk agent update <name> --add-tool=calculator --remove-tool=echo
adk agent delete <name>

# --- Agent Execution Command (Uses Redis Definition - Ephemeral) ---
# Loads definition, starts agent, runs task, stops agent, displays structured results.
adk agent execute <name> "Your task description here"
adk agent execute multi_cli_test "Get a random number then add 100 to it"

# --- Agent Start Verification (Ephemeral) ---
adk agent start <name>

# --- Web Server ---
adk web start --port=5000

# --- Utility ---
adk compile-sass
```

## Core Concepts

*   **Agent (`ADK::Agent`):** The central runtime entity that manages state, tools, planning, and execution.
*   **Tool (`ADK::Tool`):** Represents a capability (e.g., `Calculator`, `RandomNumberTool`). Tools define metadata and return standardized **Hash Results** (`{status: :success/:error, result:/error_message: ...}`).
*   **Tool Registry (`ADK::ToolRegistry`):** A singleton module that automatically registers available `Tool` classes. Used by the UI, CLI, and Agent start process.
*   **Planner (`ADK::Planner`):** Responsible for taking a high-level task and creating a **Multi-Step Execution Plan** (an array of tool calls). Uses Google Gemini and requires a `GOOGLE_API_KEY`. Receives the list of tools available to the specific running agent instance.
*   **Redis Persistence**: Agent **definitions** (name, description, list of configured tool names) are stored permanently in Redis. This data survives server restarts.
*   **Runtime State**: The set of *actively running* agent instances is managed in an in-memory hash **only within the Web UI process** (`ADK::Web::App`). This state is lost when the web server restarts.
*   **CLI vs. Web Runtime**: The CLI `agent execute` and `agent start` commands operate on *temporary*, *ephemeral* instances based on Redis definitions and exit upon completion. They **do not** interact with the persistent runtime state managed by the Web UI process.

## Development

After checking out the repo:

1.  **Install Dependencies:**
    ```bash
    bundle install
    ```
2.  **Setup Environment:**
    *   Ensure Redis is running.
    *   Create a `.env` file with `RACK_ENV=development` and your `GOOGLE_API_KEY`. Set `ADK_LOG_LEVEL` if desired (e.g., `DEBUG` for planner details).
3.  **Run Web UI:**
    ```bash
    adk web start
    ```
4.  **(Optional) Run Checks/Tasks:** Use Bundler to execute Rake tasks:
    ```bash
    bundle exec rake spec     # Run RSpec tests
    bundle exec rake rubocop  # Run Rubocop linting
    bundle exec rake yard     # Generate YARD documentation
    bundle exec rake sass     # Compile Sass manually
    bundle exec rake          # Run default tasks (spec, sass)
    ```

### Sass Compilation

The web UI uses Sass (`.scss`). Compilation happens automatically via `adk web start` but can also be triggered manually (`bundle exec rake sass` or `bin/compile-sass`).

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/tweibley/adk-ruby](https://github.com/tweibley/adk-ruby).

## License

If you are DHH or work at Basecamp/37signals you absolutely cannot use this.