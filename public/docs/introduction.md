# Welcome to the Agent Development Kit (ADK) Documentation

The Agent Development Kit (ADK) for Ruby is a comprehensive framework designed to simplify the creation, management, and deployment of sophisticated AI agents. Whether you're building simple task-oriented bots or complex, multi-tool agents capable of intricate planning, the ADK provides the foundational components and a streamlined workflow to accelerate your development process.

This documentation will guide you through understanding the core principles of ADK, setting up your development environment, utilizing its built-in features, and extending its capabilities to suit your specific needs.

## What is ADK?

ADK is a Ruby-based toolkit that empowers developers to:

*   **Define Agent Capabilities:** Easily specify an agent's instructions, the tools it can use, the AI model it leverages (e.g., from Google's Gemini family), and its operational parameters.
*   **Manage Agent Lifecycle:** Control how agents are started, how they process tasks, and how they are stopped or updated.
*   **Utilize a Rich Toolset:** Leverage a variety of built-in tools (like calculators, webhooks, and even tools that delegate tasks to other agents) or create your own custom tools.
*   **Handle Complex Interactions:** Employ a planner that enables agents to break down complex requests into a sequence of tool calls.
*   **Persist and Manage State:** Use session services and definition stores (with support for Redis) to manage conversational history and agent configurations.
*   **Integrate with External Systems:** Expose agents via web UIs, connect them to messaging platforms, or trigger them with webhooks.
*   **Deploy with Ease:** Generate deployment assets (like Dockerfiles and cloud configuration scripts) to run your ADK applications in various environments.

## Getting Started

To begin your journey with ADK, we recommend the following steps:

1.  **Understand the Fundamentals:** Familiarize yourself with the [Core Concepts](./core_concepts/adk_architecture_overview.md) that underpin the ADK, such as the [Agent Lifecycle](./core_concepts/adk_agent_lifecycle.md), [Tools and Registry](./tools/adk_tools_and_registry.md), and [Session Management](./core_concepts/adk_session_service.md).
2.  **Setup Your Environment:** Ensure you have Ruby and Bundler installed. Most ADK projects will start by adding `adk-ruby` to their `Gemfile`.
3.  **Explore the Configuration:** Learn how to configure ADK globally and per agent by reviewing the [ADK Configuration](./core_concepts/adk_configuration.md) guide.
4.  **Try the CLI:** Use the [ADK Command-Line Interface](./cli/adk_cli_usage.md) to manage agent definitions, run the web UI, and interact with other ADK components.
5.  **Run an Example:** (Consider adding a link to a simple example if one exists in the `examples/` directory or a basic "Hello World" type guide).

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

*   **[Core Concepts](./core_concepts/):** Deep dives into the fundamental building blocks and architecture of ADK.
*   **[Guides](./guides/):** Practical step-by-step instructions for common tasks and integrations.
*   **[CLI Reference](./cli/adk_cli_usage.md):** Detailed information on using the `adk` command-line tool.
*   **[Web UI Overview](./web_ui/adk_web_ui.md):** Information about the built-in web interface.
*   **[Built-in Tools Reference](./tools/adk_built_in_tools.md):** Documentation for the tools that come packaged with ADK.
*   **[Error Handling](./error_handling/adk_error_handling.md):** Guidance on understanding and managing errors within ADK.

We hope this documentation helps you build amazing AI agents with ADK! 