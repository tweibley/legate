# Documentation: ADK MCP Server Example (`examples/adk_mcp_server_resource_example.rb`)

This document explains the setup and components of the primary ADK MCP server example.

## Purpose

The goal of this example is to demonstrate how to integrate the ADK (Agent Development Kit) with the MCP (Model Context Protocol) using the `fast-mcp` library. It showcases several patterns for exposing ADK functionality over MCP:

1.  **Exposing a multi-tool ADK Agent:** Providing a single, natural language interface (`run_agent_master_agent`) that can leverage multiple underlying ADK tools.
2.  **Exposing ADK functionality as MCP Resources:** Making specific data or state derived from ADK tools available as standard MCP resources (`random_number`, `catfact`).
3.  **Exposing dedicated MCP Tools:** Creating specific MCP tools (`getrandomnumber`, `getcatfact`) that interact directly with the defined MCP resources.

## Core Components

*   **ADK (`adk` gem):** Provides the core concepts of Agents, Tools, Sessions, etc.
*   **FastMcp (`fast-mcp` gem):** Provides the MCP server implementation, including base classes for Tools and Resources.
*   **ADK Agent (`ADK::Agent`):** The central orchestrator within ADK. It uses a planner (powered by an LLM like Gemini or Claude) to interpret user requests and decide which tools to use.
*   **ADK Tools (`ADK::Tools::*`):** Specific capabilities the agent can use (e.g., `Calculator`, `CatFacts`, `Echo`).
*   **Session Service (`ADK::SessionService::InMemory`):** Manages the conversational state for agent interactions (though used ephemerally in this adapter).
*   **Direct Agent Adapter (`ADK::Mcp::Server::AdkDirectAgentAdapter`):** A custom adapter created to bridge an *instance* of `ADK::Agent` (configured in Ruby code) to the MCP server as a single `FastMcp::Tool`.
*   **MCP Resources (`RandomNumberResource`, `CatFactResource`):** Custom classes inheriting from `FastMcp::Resource` that provide access to specific data derived from ADK tool functionality (random numbers, cat facts).
*   **MCP Tools (`GetNewRandomNumberTool`, `GetNewCatFactTool`):** Custom classes inheriting from `FastMcp::Tool` designed to directly interact with the custom MCP Resources.

## Setup Explained

1.  **Loading Dependencies:** The script requires `adk`, `fast_mcp`, and necessary ADK components like `Agent`, `SessionService`, the specific `AdkDirectAgentAdapter`, and all the ADK tool classes (`Calculator`, `CatFacts`, etc.). It also requires `net/http` and `uri` for the `CatFactResource`.

2.  **Defining MCP Resources:**
    *   `RandomNumberResource`: A simple resource that generates a new random float every time its `read` method is called (via an MCP `readResource` request). It exposes itself at the URI `random_number`.
    *   `CatFactResource`: Fetches a fact from `catfact.ninja` whenever its `read` method is called. It exposes itself at the URI `catfact`.

3.  **Defining Resource-Specific MCP Tools:**
    *   `GetNewRandomNumberTool`: A simple MCP tool named `getrandomnumber` that directly calls `RandomNumberResource.instance.read` to get and return a random number.
    *   `GetNewCatFactTool`: An MCP tool named `getcatfact` that calls `CatFactResource.instance.read` to get and return a cat fact.

4.  **Instantiating the Master ADK Agent:**
    *   An `ADK::Agent` instance named `master_agent` is created.
    *   It's configured with the `gemini-2.0-flash` model.
    *   Crucially, it's given a list (`all_tool_classes`) containing the *classes* of all standard ADK tools (`ADK::Tools::Calculator`, `ADK::Tools::CatFacts`, etc.).

5.  **Instantiating Session Service:** An `ADK::SessionService::InMemory` instance is created. This is required by the adapter to manage temporary session state during the agent's execution for a single call.

6.  **Wrapping the Agent:**
    *   `ADK::Mcp::Server::AdkDirectAgentAdapter.wrap(master_agent, session_service)` is called.
    *   This dynamically creates a new class (`AdaptedMasterAgentTool`) that inherits from `FastMcp::Tool`.
    *   This generated tool class knows how to:
        *   Accept a single `prompt` argument (defined in its `arguments` block).
        *   Use the provided `master_agent` instance and `session_service`.
        *   Create a temporary session for the agent.
        *   Call the `master_agent.run_task` method with the prompt.
        *   Process the agent's result (success, error, or pending).
        *   Clean up the temporary session.
    *   The generated tool registers itself with MCP under the name `run_agent_master_agent`.

7.  **Setting up the MCP Server:**
    *   A `FastMcp::Server` instance is created.
    *   The custom resources (`RandomNumberResource`, `CatFactResource`) are registered.
    *   The custom tools (`GetNewRandomNumberTool`, `GetNewCatFactTool`) AND the wrapped agent tool (`AdaptedMasterAgentTool`) are registered.

8.  **Starting the Server:**
    *   `mcp_server.start` begins listening for MCP requests on STDIN/STDOUT.
    *   The server announces the available resources and tools.

## Why this setup?

*   **Flexibility:** The `run_agent_master_agent` tool provides a powerful, natural language interface. Users can ask it to perform calculations, get cat facts, echo messages, etc., without needing to know the specific underlying ADK tool names or parameters. The agent handles the planning.
*   **Direct Access:** Exposing `random_number` and `catfact` as resources allows MCP clients that *only* care about that specific piece of data to access it directly using standard `readResource` calls, without needing to go through the agent.
*   **Demonstration:** Shows different ways to bridge ADK and MCP, catering to different client needs and interaction styles.
*   **Simplicity (Agent Definition):** Using the `AdkDirectAgentAdapter` allows defining the agent's configuration directly within the Ruby script, avoiding the need for external definitions (like in Redis) for this specific example.

## How to Run

From the root of the `adk-ruby` project:

```bash
# Just run the server (requires an MCP client to connect)
bundle exec ruby examples/adk_mcp_server_resource_example.rb

# Or run with the MCP Inspector for a web UI
npx @modelcontextprotocol/inspector -- bundle exec ruby examples/adk_mcp_server_resource_example.rb
``` 