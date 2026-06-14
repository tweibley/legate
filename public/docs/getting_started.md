# Getting Started with Legate

This guide will walk you through setting up your first Legate project using the `skaffold` command.

## Prerequisites

Before you begin, ensure you have the following installed:

*   **Ruby** (version 3.4 or higher is required)
*   **Bundler** (`gem install bundler`)

## 1. Install the Legate Gem

First, install the `legate` gem globally or add it to your Gemfile.

```bash
gem install legate
```

## 2. Create a New Project

The easiest way to start is by using the `skaffold` command. This will generate a complete directory structure with sample files.

```bash
legate skaffold my-awesome-agent
```

This will create a directory named `my-awesome-agent` with the following structure:

*   `Gemfile`: Dependency definitions.
*   `config.ru`: Configuration for running the Legate Web UI.
*   `agents/`: Directory for your agent definitions.
    *   `hello_world_agent.rb`: A simple sample agent that uses the sample tool.
*   `tools/`: Directory for custom tools.
    *   `sample_tool.rb`: A sample tool implementation.
*   `.env.example`: Template for environment variables.
*   `bin/`: Helper scripts.
    *   `console`: Starts an IRB console with your agents loaded.

## 3. Configure Your Environment

Navigate into your new project directory:

```bash
cd my-awesome-agent
```

Copy the example environment file:

```bash
cp .env.example .env
```

Open `.env` and add your configuration, specifically your `GOOGLE_API_KEY` if you plan to use Gemini models.

```bash
GOOGLE_API_KEY=your_actual_api_key_here
```

## 4. Install Dependencies

Run Bundler to install the required gems:

```bash
bundle install
```

## 5. Run the Application

You can now start the Legate Web UI to interact with your agents.

```bash
bundle exec legate web start
```

By default, this starts the server at `http://localhost:4567` (override with `--port`). Open this URL in your browser to see the Legate dashboard.

## 6. Interact with Your Agent

**From the Web UI:**

1.  In the Web UI, go to the "Agents" tab.
2.  You should see the `hello_world` agent.
3.  Click "Start Chat" (or similar).
4.  Type "Say hello!" and see the agent respond.

**From Ruby code** — the quickest path is `Agent#ask`, which starts the agent,
runs the task, and returns the final event:

```ruby
require 'legate'

agent = Legate::Agent.new(definition: Legate::AgentDefinition.new.define do |a|
  a.name :hello_world
  a.description 'Greets the user.'
  a.instruction 'Say hello back to the user.'
  a.use_tool :echo
end)

puts agent.ask('Say hello!').answer
```

Call `.answer` for the result, or `.success?` / `.error_message` to branch on the
outcome. Pass `session_id:` to continue a conversation, and a block to watch
progress live (`agent.ask('…') { |event| ... }`).

## Next Steps

*   **Create more agents:** Use `legate agent generate my_new_agent` to create more agents.
*   **Learn about Tools:** Check out the [Built-in Tools Reference](./tools/legate_built_in_tools) to see what tools are available.
*   **Deploy:** When you're ready, use `legate deployment generate` to prepare for cloud deployment.
