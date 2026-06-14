# Exposing Legate Components via MCP

This guide explains how to make your `Legate::Tool`s (and experimentally, `Legate::Agent`s) available to external MCP clients. This is achieved by using provided adapters with the [`fast-mcp`](https://github.com/yjacquin/fast-mcp) Ruby gem, which handles the MCP server implementation.

**Prerequisite**: You must have the `fast-mcp` gem included in your project's Gemfile and installed (`bundle add fast_mcp`).

## Architecture Overview: Legate as MCP Service Provider

The following diagram illustrates how Legate components are wrapped and exposed via `fast-mcp`:

```mermaid
graph LR
    subgraph Your Ruby Application / Script
        LegateTool["Your Legate::Tool Class"] -- Wrapped by --> Adapter["Legate::Mcp::Server::LegateToolAdapter"]
        LegateAgent["Your Legate::Agent Definition/Instance"] -- Wrapped by --> AgentAdapter["Legate::Mcp::Server::LegateAgentAdapter"]
        Adapter -- Registers with --> FastMcpServer["fast-mcp Server Instance"]
        AgentAdapter -- Registers with --> FastMcpServer
        FastMcpServer -- Manages --> Transport["fast-mcp Transport (STDIO/Rack)"]
    end

    subgraph External MCP Client
        MCP_Client["External MCP Client"]
    end

    Transport -- JSON-RPC --> MCP_Client

    style LegateTool fill:#ccf,stroke:#333,stroke-width:2px
    style LegateAgent fill:#ccf,stroke:#333,stroke-width:2px
    style Adapter fill:#cff,stroke:#333,stroke-width:2px
    style AgentAdapter fill:#cff,stroke:#333,stroke-width:2px
    style FastMcpServer fill:#fcf,stroke:#333,stroke-width:2px
    style MCP_Client fill:#f9f,stroke:#333,stroke-width:2px
```

**Key Components:**

*   **`Legate::Tool` / `Legate::Agent`**: Your existing Legate components.
*   **`Legate::Mcp::Server::LegateToolAdapter`**: Wraps an `Legate::Tool` class to make it compatible with `fast-mcp`.
*   **`Legate::Mcp::Server::LegateAgentAdapter` / `LegateDirectAgentAdapter`**: Wraps an `Legate::Agent` (either a registry definition or a direct instance) to expose it as a single MCP tool.
*   **`fast-mcp Server Instance`**: The MCP server provided by the `fast-mcp` gem.
*   **`fast-mcp Transport`**: How the `fast-mcp` server communicates (e.g., STDIO, Rack middleware for HTTP/SSE).

## 1. Exposing Legate Tools

Use the `Legate::Mcp::Server::LegateToolAdapter.wrap` method to create a `fast-mcp` compatible tool class from your existing `Legate::Tool` subclass.

### 1.1. Wrapping a Tool

```ruby
require 'legate'
require 'fast_mcp'
require 'legate/mcp/server/legate_tool_adapter'
require 'legate/tools/calculator' # Example Legate tool

# Configure Legate logger if needed
# Legate.configure { |c| c.log_level = Logger::INFO }

# 1. Wrap your Legate::Tool class
AdaptedCalculatorTool = Legate::Mcp::Server::LegateToolAdapter.wrap(Legate::Tools::Calculator)

# 2. Create and configure the fast-mcp server
mcp_server = FastMcp::Server.new(
  name: 'legate-tool-server',
  version: Legate::VERSION,
  logger: Legate.logger # Optional: Use Legate's logger
)

# 3. Register the adapted tool with the fast-mcp server
mcp_server.register_tool(AdaptedCalculatorTool)

# 4. Start the server (e.g., using STDIO transport)
Legate.logger.info("Starting Legate MCP Tool Server via STDIO...")
mcp_server.start # This will block and listen on STDIN/STDOUT
```

### 1.2. How it Works (Tool Adapter)

*   `LegateToolAdapter.wrap(YourLegateToolClass)`:
    *   Retrieves metadata (name, description, parameters) from `YourLegateToolClass`.
    *   Uses `Legate::Mcp::Util::SchemaConverter.legate_to_dry_schema` to convert Legate parameter definitions into a `Dry::Schema` block for `fast-mcp` argument validation. (See [Schema Conversion Details](../advanced/mcp_schema_conversion))
    *   Dynamically creates a new class that inherits from `FastMcp::Tool`.
    *   The `call` method of this new class will:
        *   Instantiate `YourLegateToolClass`.
        *   Create a dummy `Legate::ToolContext` (as there's no Legate session in this server context).
        *   Execute `your_legate_tool_instance.execute(params, dummy_context)`.
        *   Translate the Legate result hash (`{status: :success, result: ...}` or `{status: :error, ...}`) into a format `fast-mcp` expects (either direct result or raises an error).

### 1.3. Handling Asynchronous Legate Tools

If your Legate tool is asynchronous (returns `{status: :pending, job_id: ...}`), the `LegateToolAdapter` will return a corresponding MCP-friendly pending response (e.g., `{'status': 'pending', 'job_id': '...'}`).

To allow clients to check the status of these jobs, you **must** also wrap and expose the `Legate::Tools::CheckJobStatusTool`:

```ruby
require 'legate/tools/base_async_job_tool' # If defining your own async tool
require 'legate/tools/sleepy_tool'       # Example Legate async tool
require 'legate/tools/check_job_status_tool'

# ... (fast_mcp server setup) ...

AdaptedSleepyTool = Legate::Mcp::Server::LegateToolAdapter.wrap(Legate::Tools::SleepyTool)
AdaptedCheckJobStatusTool = Legate::Mcp::Server::LegateToolAdapter.wrap(Legate::Tools::CheckJobStatusTool)

mcp_server.register_tool(AdaptedSleepyTool)
mcp_server.register_tool(AdaptedCheckJobStatusTool) # Crucial for async tools!

# ... (start server) ...
```
Clients will then call your async tool, get a `job_id`, and use the exposed `check_job_status` tool to poll for completion.

## 2. Exposing Legate Agents (Experimental)

You can wrap an entire Legate Agent and expose its `run_task` functionality as a single MCP tool. This is useful for providing a simple, prompt-based interface to your agent for external MCP clients.

Two adapters are available:

*   **`Legate::Mcp::Server::LegateAgentAdapter`**: For agents defined and stored in the **`GlobalDefinitionRegistry`** (e.g., created via `legate agent save`).
*   **`Legate::Mcp::Server::LegateDirectAgentAdapter`**: For `Legate::Agent` instances created directly in your Ruby code.

### 2.1. Using `LegateAgentAdapter` (Registry Definition)

**Prerequisites:**
*   Your agent definition must exist in the `GlobalDefinitionRegistry`.
*   An `Legate::SessionService` instance is needed by the adapter for temporary session management.

```ruby
require 'legate/mcp/server/legate_agent_adapter'
require 'legate/session_service/in_memory'

AGENT_NAME_IN_REGISTRY = 'my_chat_agent' # The name of your agent in the registry
session_service = Legate::SessionService::InMemory.new

# 1. Wrap the agent definition from the registry
AdaptedRegistryAgent = Legate::Mcp::Server::LegateAgentAdapter.wrap(AGENT_NAME_IN_REGISTRY, session_service)

# 2. Setup fast-mcp server and register AdaptedRegistryAgent
# ... (as shown in Tool Adapter example) ...
mcp_server.register_tool(AdaptedRegistryAgent)
# ... (start server) ...
```
This will expose a tool named something like `run_agent_my_chat_agent` that accepts a `prompt` argument.

### 2.2. Using `LegateDirectAgentAdapter` (Ruby Instance)

**Prerequisites:**
*   An `Legate::Agent` instance created in your Ruby code.
*   An `Legate::SessionService` instance.

```ruby
require 'legate/mcp/server/legate_direct_agent_adapter'
require 'legate/session_service/in_memory'
require 'legate/tools/echo' # Example tool for the agent

# 1. Create your Legate Agent instance from a definition.
#    Tools are selected on the definition via use_tool; ensure the tool
#    class is registered globally so the agent can find it.
Legate::GlobalToolManager.register_tool(Legate::Tools::Echo)

agent_definition = Legate::AgentDefinition.new.define do |a|
  a.name :my_code_defined_agent
  a.instruction 'Echo the user input.'
  a.use_tool :echo
end

my_agent_instance = Legate::Agent.new(definition: agent_definition)
# Do NOT call my_agent_instance.start() here if only using for MCP wrapping.

session_service = Legate::SessionService::InMemory.new

# 2. Wrap the agent *instance*
AdaptedDirectAgent = Legate::Mcp::Server::LegateDirectAgentAdapter.wrap(my_agent_instance, session_service)

# 3. Setup fast-mcp server and register AdaptedDirectAgent
# ... (as shown in Tool Adapter example) ...
mcp_server.register_tool(AdaptedDirectAgent)
# ... (start server) ...
```
This will expose a tool named `run_agent_my_code_defined_agent`.

### 2.3. Agent Adapter Limitations (Current Version)

*   **Stateless Execution**: Each call to the wrapped agent tool via MCP is treated as a new, isolated interaction. A temporary Legate session is created for the `run_task` call and then deleted. There is no persistent conversation history between MCP calls to the agent tool.
*   **Tool Availability**: For the `LegateAgentAdapter` (registry-based), any tools specified in the agent's definition must be available in the global `Legate::ToolRegistry` of the Ruby process running the MCP server.

## 3. Server Setup with `fast-mcp`

`fast-mcp` offers different ways to run the MCP server:

*   **STDIO Server (`FastMcp::Server.new` or `FastMcp::Server::Stdio.new`)**:
    *   Listens for JSON-RPC messages on standard input and writes responses to standard output.
    *   Ideal for local development, integration with tools that manage child processes (like `mcp-inspector`), or simple standalone tool/agent servers.
    *   Start by calling `mcp_server.start`.
    *   See `examples/15_mcp_server.rb`.
*   **Rack Middleware (`FastMcp.rack_middleware`)**:
    *   Integrates the MCP server into any Rack-based web application (e.g., Sinatra, Rails).
    *   Adds MCP endpoints (typically `/mcp/messages` for POST and `/mcp/sse` for Server-Sent Events) to your existing app.
    *   Allows clients to connect via HTTP/SSE.
    *   See `examples/advanced/mcp/mcp_server_rack.rb`.

Refer to the [`fast-mcp` documentation](https://github.com/yjacquin/fast-mcp) for more details on server setup, authentication, and other advanced features.

## 4. Security Considerations

*   When exposing tools and agents via MCP, you are making their functionality available to any client that can connect to your `fast-mcp` server.
*   If using the Rack middleware for an HTTP-accessible server, consider appropriate network security (firewalls, private networks) and authentication mechanisms if needed. `fast-mcp` provides options for token-based authentication (`FastMcp.authenticated_rack_middleware`) and origin checks.
*   Be mindful of the capabilities of the Legate tools and agents you expose. Avoid exposing components that could lead to unintended actions or data access if called by unauthorized clients. 