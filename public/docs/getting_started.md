# Getting Started with ADK

This guide will walk you through setting up your first Agent Development Kit (ADK) project using the `skaffold` command.

## Prerequisites

Before you begin, ensure you have the following installed:

*   **Ruby** (version 3.0 or higher is recommended)
*   **Bundler** (`gem install bundler`)
*   **Redis** (Optional, but recommended for persistent sessions)

## 1. Install the ADK Gem

First, install the `adk-ruby` gem globally or add it to your Gemfile.

```bash
gem install adk-ruby
```

## 2. Create a New Project

The easiest way to start is by using the `skaffold` command. This will generate a complete directory structure with sample files.

```bash
adk skaffold my-awesome-agent
```

This will create a directory named `my-awesome-agent` with the following structure:

*   `Gemfile`: Dependency definitions.
*   `config.ru`: Configuration for running the ADK Web UI.
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
REDIS_URL=redis://localhost:6379
```

## 4. Install Dependencies

Run Bundler to install the required gems:

```bash
bundle install
```

## 5. Run the Application

You can now start the ADK Web UI to interact with your agents.

```bash
bundle exec rackup
```

By default, this will start the server at `http://localhost:9292`. Open this URL in your browser to see the ADK dashboard.

## 6. Interact with Your Agent

1.  In the Web UI, go to the "Agents" tab.
2.  You should see the `hello_world` agent.
3.  Click "Start Chat" (or similar).
4.  Type "Say hello!" and see the agent respond.

## Next Steps

*   **Create more agents:** Use `adk agent generate my_new_agent` to create more agents.
*   **Learn about Tools:** Check out the [Built-in Tools Reference](../tools/adk_built_in_tools) to see what tools are available.
*   **Deploy:** When you're ready, use `adk deployment generate` to prepare for cloud deployment.
