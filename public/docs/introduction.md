# Welcome to the Legate Documentation

Legate — AI Agent Framework for Ruby — is a comprehensive framework designed to simplify the creation, management, and deployment of sophisticated AI agents. Whether you're building simple task-oriented bots or complex, multi-tool agents capable of intricate planning, the Legate provides the foundational components and a streamlined workflow to accelerate your development process.

This documentation will guide you through understanding the core principles of Legate, setting up your development environment, utilizing its built-in features, and extending its capabilities to suit your specific needs.

## What is Legate?

Legate is a Ruby-based toolkit that empowers developers to:

*   **Define Agent Capabilities:** Easily specify an agent's instructions, the tools it can use, the AI model it leverages (e.g., from Google's Gemini family), and its operational parameters.
*   **Manage Agent Lifecycle:** Control how agents are started, how they process tasks, and how they are stopped or updated.
*   **Utilize a Rich Toolset:** Leverage a variety of built-in tools (like calculators, webhooks, and even tools that delegate tasks to other agents) or create your own custom tools.
*   **Handle Complex Interactions:** Employ a planner that enables agents to break down complex requests into a sequence of tool calls.
*   **Persist and Manage State:** Use session services and definition stores to manage conversational history and agent configurations.
*   **Integrate with External Systems:** Expose agents via web UIs, connect them to messaging platforms, or trigger them with webhooks.
*   **Deploy with Ease:** Generate deployment assets (like Dockerfiles and cloud configuration scripts) to run your Legate applications in various environments.

## Getting Started

To begin your journey with Legate, we recommend the following steps:

1.  **Understand the Fundamentals:** Familiarize yourself with the [Core Concepts](./core_concepts/legate_architecture_overview) that underpin the Legate, such as the [Agent Lifecycle](./core_concepts/legate_agent_lifecycle), [Tools and Registry](./tools/legate_tools_and_registry), and [Session Management](./core_concepts/legate_session_service).
2.  **Setup Your Environment:** Ensure you have Ruby and Bundler installed. Most Legate projects will start by adding `legate` to their `Gemfile`.
3.  **Explore the Configuration:** Learn how to configure Legate globally and per agent by reviewing the [Legate Configuration](./core_concepts/legate_configuration) guide.
4.  **Try the CLI:** Use the [Legate Command-Line Interface](./cli/legate_cli_usage) to manage agent definitions, run the web UI, and interact with other Legate components.
5.  **Run an Example:** Browse the [Examples Guide](./examples) for 16 hands-on examples covering every major feature, from basic agents to MCP integration.

## Key Features

*   **Modular Architecture:** Easily extendable and customizable.
*   **Powerful Planner:** Enables multi-step reasoning and tool usage.
*   **Rich Tool Ecosystem:** Comes with several built-in tools and a clear interface for adding new ones.
*   **Agent Definition Store:** Persistently store and manage your agent configurations.
*   **Session Management:** Track conversation history and agent state.
*   **Web UI:** A built-in Sinatra application for managing agents and viewing sessions.
*   **CLI for Management:** Robust command-line tools for development and administration.
*   **Deployment Assistance:** Tools to generate Dockerfiles and deployment scripts.

## Navigating these Docs

This documentation is organized into several key areas:

*   **[Core Concepts](./core_concepts/):** Deep dives into the fundamental building blocks and architecture of Legate.
*   **[Guides](./guides/):** Practical step-by-step instructions for common tasks and integrations.
*   **[CLI Reference](./cli/legate_cli_usage):** Detailed information on using the `legate` command-line tool.
*   **[Web UI Overview](./web_ui/legate_web_ui):** Information about the built-in web interface.
*   **[Built-in Tools Reference](./tools/legate_built_in_tools):** Documentation for the tools that come packaged with Legate.
*   **[Error Handling](./error_handling/legate_error_handling):** Guidance on understanding and managing errors within Legate.

We hope this documentation helps you build amazing AI agents with Legate! 