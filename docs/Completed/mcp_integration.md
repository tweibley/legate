# ADK-Ruby: Model Context Protocol (MCP) Integration Guide

This document explains how to integrate `adk-ruby` with the Model Context Protocol (MCP) standard, enabling interoperability with external tools and servers.

## 1. Using External MCP Tools (ADK as Client)

You can configure an `ADK::Agent` to connect to external MCP servers (e.g., one run via `npx @modelcontextprotocol/server-filesystem`) and use the tools provided by that server alongside its native ADK tools.

### 1.1 Configuration

Configure the agent by passing an array of server configurations to the `mcp_servers` option during initialization. Each configuration hash specifies the connection type and necessary parameters.

**Currently Supported Connection Types:**
*   `:stdio`: Connects to a local process using standard input/output.
    *   `command`: The command to execute (e.g., 'npx').
    *   `args`: An array of arguments for the command (e.g., `['@modelcontextprotocol/server-filesystem', '--stdio']`).

```ruby
require 'adk'
require 'adk/mcp' # Ensure MCP modules are loaded

# Configuration for an MCP server running via STDIO
mcp_server_config = {
  type: :stdio,
  command: 'npx', # The command to run
  args: ['@modelcontextprotocol/server-filesystem', '--stdio', 'path/to/your/tools'] # Example args
}

# Define native tool classes if needed
class MyNativeTool < ADK::Tool
  define_metadata(name: :native_tool, description: 'Does something natively')
  def perform_execution(params, context); { status: :success, result: 'Native OK' }; end
end

# Create the agent, passing the MCP server config and any native tools
my_agent = ADK::Agent.new(
  name: 'mcp_client_agent',
  description: 'An agent that uses external MCP tools.',
  tool_classes: [MyNativeTool], # Optional native tools
  mcp_servers: [mcp_server_config] # Pass MCP config(s) as an array
)

# Start the agent runtime
# This automatically connects to configured MCP servers and discovers tools.
my_agent.start

ADK.logger.info("Agent initialized. Available tools: #{my_agent.available_tools_metadata.map { |t| t[:name] }}")

# Example: Run a task that might use an external tool (requires session setup)
# session_service = ADK::SessionService::InMemory.new
# session = session_service.create_session(app_name: 'mcp_test', user_id: 'user1')
# final_event = my_agent.run_task(
#   session_id: session.id,
#   user_input: "Read the file 'my_document.txt' using the filesystem tool.", # Assuming server provides a file tool
#   session_service: session_service
# )
# ADK.logger.info("Agent Result: #{final_event.content}")

# Stop the agent runtime
# This automatically disconnects from MCP servers.
my_agent.stop

For a complete runnable example demonstrating this client-side setup, see [`examples/mcp_client_agent_example.rb`](../examples/mcp_client_agent_example.rb).

### 1.2 How it Works (Client-Side)

1.  **Initialization:** The agent stores the `mcp_servers` configuration.
2.  **`agent.start`:**
    *   The agent iterates through the `mcp_servers` config.
    *   For each config, it creates an `ADK::Mcp::Client` instance.
    *   `client.connect` is called, establishing the connection (e.g., launching STDIO process) and performing the MCP `initialize` handshake.
    *   `client.list_tools` retrieves the available tool schemas from the MCP server.
    *   For each schema, `ADK::Mcp::ToolWrapper.from_mcp_schema` dynamically creates an `ADK::Tool` proxy subclass.
    *   This proxy class is registered with the *agent's specific* `ToolRegistry`.
3.  **Planning:** The `ADK::Planner` queries the agent for available tools (using `agent.available_tools_metadata`) which now includes both native and registered MCP proxy tools.
4.  **Execution:** If the planner selects an MCP proxy tool:
    *   The agent calls the proxy tool's `execute` method.
    *   The proxy's `perform_execution` method uses the stored `ADK::Mcp::Client` instance to call `client.call_tool` with the appropriate tool name and arguments.
    *   The external MCP server executes the actual tool.
    *   The result or error is sent back through the client and mapped to the standard ADK status hash (`{status: :success, ...}` or `{status: :error, ...}`).
5.  **`agent.stop`:**
    *   The agent calls `disconnect` on all active `ADK::Mcp::Client` instances, terminating connections.

### 1.3 Client-Side Error Handling

*   **Connection Errors:** If an `ADK::Mcp::Client` fails to connect during `agent.start` (e.g., command not found, handshake fails), an error is logged, and that specific MCP server will be unavailable, but the agent will typically continue starting with its native tools.
*   **Execution Errors:** If an error occurs during the execution of an external MCP tool (`client.call_tool`):
    *   **Communication Errors:** (`ADK::Mcp::ConnectionError`, `ADK::Mcp::ProtocolError`) These indicate problems talking to the MCP server itself. They are caught by the `ToolWrapper` and result in an ADK `:error` status hash with a message like "MCP Communication Error: ...".
    *   **Remote Tool Errors:** (`ADK::Mcp::RemoteToolError`) These occur when the external MCP server successfully executed the tool, but the tool *itself* reported an error. The `ToolWrapper` converts this into an ADK `:error` status hash, often including the original error message, code, and data from the MCP server in the `error_details` field.
*   **Agent Behavior:** In general, if a step involving an external MCP tool fails, the agent's plan execution will halt (similar to native tool failures), and the final agent response will reflect the error status hash provided by the `ToolWrapper`.

## 2. Exposing ADK Components via MCP (using `fast-mcp`)

You can make your custom `ADK::Tool`s (and experimentally, `ADK::Agent`s) available to external MCP clients by using the provided adapters with the [`fast-mcp`](https://github.com/yjacquin/fast-mcp) Ruby gem.

**(Requires `fast-mcp` gem in your Gemfile: `gem 'fast-mcp'`)**

### 2.1 Exposing ADK Tools

Use the `ADK::Mcp::Server::AdkToolAdapter.wrap` method to create a `fast-mcp` compatible tool class from your existing `ADK::Tool` subclass.

```ruby
# --- Server Example (e.g., in examples/mcp_adk_tool_server.rb) --- 
require 'bundler/setup'
require 'adk'
require 'fast_mcp' 
require 'adk/mcp/server/adk_tool_adapter'
require 'adk/tools/check_job_status_tool' # Needed for async

# Configure ADK logger if needed
ADK.configure { |c| c.log_level = Logger::INFO }

# --- Define or require your ADK::Tool subclasses ---
class MyCalculatorTool < ADK::Tool
  define_metadata(
    name: :my_calculator,
    description: 'Performs simple calculations.',
    parameters: {
      a: { type: :numeric, required: true, description: 'First number' },
      b: { type: :numeric, required: true, description: 'Second number' },
      op: { type: :string, required: true, description: 'Operation (+, -, *, /)' }
    }
  )
  def perform_execution(params, context)
    a = params[:a]; b = params[:b]
    case params[:op]
    when '+' then { status: :success, result: a + b }
    when '-' then { status: :success, result: a - b }
    when '*' then { status: :success, result: a * b }
    when '/' then b.zero? ? { status: :error, error_message: 'Division by zero' } : { status: :success, result: a / b }
    else { status: :error, error_message: "Unknown op: #{params[:op]}" }
    end rescue { status: :error, error_message: "Calc error: #{e.message}" }
  end
end

# Example Async Tool (Requires Sidekiq setup)
class MyAsyncTool < ADK::Tools::BaseAsyncJobTool
  define_metadata(name: :start_long_job, description: 'Starts a job that takes time', parameters: { duration: { type: :numeric, required: true } })
  class Worker; include Sidekiq::Job; def perform(d); sleep d; "Slept for #{d}"; end; end
  def sidekiq_worker_class; Worker; end
  def prepare_job_arguments(params, context); [params[:duration]]; end
end
# --------------------------------------------------

# 1. Wrap the ADK tools
AdaptedCalculator = ADK::Mcp::Server::AdkToolAdapter.wrap(MyCalculatorTool)
AdaptedAsyncJob = ADK::Mcp::Server::AdkToolAdapter.wrap(MyAsyncTool)
AdaptedCheckJob = ADK::Mcp::Server::AdkToolAdapter.wrap(ADK::Tools::CheckJobStatusTool)

# 2. Create and configure the fast-mcp server
mcp_server = FastMcp::Server.new(
  name: 'adk-tool-server', 
  version: '1.0.0',
  logger: ADK.logger # Use ADK logger
)

# 3. Register the adapted tools
mcp_server.register_tool(AdaptedCalculator)
mcp_server.register_tool(AdaptedAsyncJob)
# IMPORTANT: Expose CheckJobStatusTool when exposing async tools!
mcp_server.register_tool(AdaptedCheckJob) 

# 4. Start the server (using STDIO transport)
puts "Starting ADK MCP Tool Server via STDIO... (Requires fast-mcp)"
mcp_server.start # Blocks here

# --- To run as a Rack app instead: ---
# require 'rack'
# require 'rack/handler/puma'
# 
# app = ->(env) { [404, {}, ['Not Found']] } # Dummy base app
# 
# mcp_middleware = FastMcp.rack_middleware(app, name: 'adk-tool-server', version: '1.0.0', logger: ADK.logger) do |server|
#   server.register_tool(AdaptedCalculator)
#   server.register_tool(AdaptedAsyncJob)
#   server.register_tool(AdaptedCheckJob)
# end
# 
# puts "Starting ADK MCP Tool Server via Rack on http://localhost:9292/mcp..."
# Rack::Handler::Puma.run mcp_middleware, Port: 9292
# --------------------------------------

For a complete runnable example demonstrating exposing tools via Rack middleware, see [`examples/mcp_server_rack.rb`](../examples/mcp_server_rack.rb).

### 2.2 Exposing ADK Agents (Experimental)

You can wrap an ADK Agent as a single MCP tool, allowing external clients to interact with the agent using a simple prompt.
There are two adapter types available depending on how your agent is defined:

1.  **`ADK::Mcp::Server::AdkAgentAdapter`:** Wraps an agent definition stored in **Redis**. (As covered in the original plan).
2.  **`ADK::Mcp::Server::AdkDirectAgentAdapter`:** Wraps an **instance** of `ADK::Agent` created directly in Ruby code.

Choose the adapter that matches your setup.

**Option A: Using `AdkAgentAdapter` (Redis Definition)**

Use this when your agent is defined using the ADK CLI (`adk agent create ...`) and stored in Redis.

**Prerequisites:**
*   An agent definition must exist in Redis.
*   A configured `ADK::SessionService` instance is required for managing temporary sessions during the ephemeral execution.

```ruby
# --- Server Example (Redis-based Agent) ---
require 'bundler/setup'
require 'adk'
require 'fast_mcp'
require 'adk/mcp/server/adk_agent_adapter' # Redis-based adapter
require 'adk/session_service/in_memory' # Or redis

ADK.configure do |config|
  config.log_level = Logger::INFO
  # Ensure Redis is configured if not using defaults
  # config.redis_options = { url: ENV.fetch('ADK_REDIS_URL', 'redis://localhost:6379/1') }
end

AGENT_NAME_IN_REDIS = 'my_redis_agent' # <<< Replace with your agent name
session_service = ADK::SessionService::InMemory.new # Or RedisSessionService

# 1. Wrap the agent definition from Redis
begin
  AdaptedAgentRedis = ADK::Mcp::Server::AdkAgentAdapter.wrap(AGENT_NAME_IN_REDIS, session_service)
rescue ADK::Mcp::Error => e
  ADK.logger.fatal("Error wrapping agent: #{e.message}. Is Redis running and agent '#{AGENT_NAME_IN_REDIS}' defined?")
  exit(1)
end

# 2. Create fast-mcp server
mcp_server = FastMcp::Server.new(name: 'adk-agent-server-redis', version: '1.0.0', logger: ADK.logger)

# 3. Register the adapted agent tool (name generated like run_agent_...)
mcp_server.register_tool(AdaptedAgentRedis)

# 4. Start the server (e.g., STDIO)
puts "Starting ADK MCP Agent Server (Redis: '#{AGENT_NAME_IN_REDIS}') via STDIO..."
mcp_server.start # Blocks here
```

For a complete runnable example demonstrating this Redis-based agent adapter setup, see [`examples/mcp_server_agent_redis.rb`](../examples/mcp_server_agent_redis.rb).

**Option B: Using `AdkDirectAgentAdapter` (Ruby Instance)**

Use this when you instantiate your `ADK::Agent` directly in your Ruby code, perhaps with dynamically determined tools or configurations.

**Prerequisites:**
*   An instance of `ADK::Agent` created in your code.
*   An instance of `ADK::SessionService`.

```ruby
# --- Server Example (Instance-based Agent) ---
require 'bundler/setup'
require 'adk'
require 'fast_mcp'
require 'adk/mcp/server/adk_direct_agent_adapter' # Direct adapter
require 'adk/session_service/in_memory'
require 'adk/tools/calculator' # Example tool for the agent
require 'adk/tools/echo'       # Example tool for the agent

ADK.configure { |config| config.log_level = Logger::INFO }

# 1. Create the ADK Agent Instance in Ruby
my_agent_instance = ADK::Agent.new(
  name: "my_direct_agent",
  description: "Agent created directly in Ruby code",
  tool_classes: [ADK::Tools::Calculator, ADK::Tools::Echo]
  # model_name: 'your-model' # Optional
)
# Note: You do NOT need to call my_agent_instance.start() here

session_service = ADK::SessionService::InMemory.new

# 2. Wrap the agent *instance*
begin
  AdaptedAgentDirect = ADK::Mcp::Server::AdkDirectAgentAdapter.wrap(my_agent_instance, session_service)
rescue ArgumentError => e
  ADK.logger.fatal("Error wrapping agent instance: #{e.message}")
  exit(1)
end

# 3. Create fast-mcp server
mcp_server = FastMcp::Server.new(name: 'adk-agent-server-direct', version: '1.0.0', logger: ADK.logger)

# 4. Register the adapted agent tool (name generated like run_agent_...)
mcp_server.register_tool(AdaptedAgentDirect)

# 5. Start the server (e.g., STDIO)
puts "Starting ADK MCP Agent Server (Direct Instance: '#{my_agent_instance.name}') via STDIO..."
mcp_server.start
```

**Limitations (Agent Adapters V1):**
*   **Stateless (Both Adapters):** Each `call` via MCP creates a temporary session, runs the task, and deletes the session. There is no conversation history between MCP calls.
*   **Redis Dependency (`AdkAgentAdapter`):** The Redis-based adapter requires connecting to Redis on every call to load the definition.
*   **Tool Loading (`AdkAgentAdapter`):** Assumes tools defined for the agent in Redis exist in the global `ADK::ToolRegistry` when the adapter runs.

For a more detailed example using the `AdkDirectAgentAdapter` alongside custom MCP Resources, see [`docs/direct_agent_adapter_example.md`](./direct_agent_adapter_example.md).

### 2.3 Server Adapter Notes

*   **Dummy Context:** The `AdkToolAdapter` and `AdkAgentAdapter` currently create a minimal `ADK::ToolContext` when executing the underlying ADK tool/agent. This context lacks session history or a real session service connection. Tools relying heavily on context details might not behave as expected when exposed via MCP.
*   **Error Handling:** If an ADK tool returns `{status: :error, error_message: ...}`, the adapter raises a `StandardError` with the message. `fast-mcp` should then convert this into a standard MCP error response. If the tool execution itself raises an unexpected exception, that is also caught and raised as a `StandardError`.
*   **Async Tools:** When exposing async tools, you *must* also wrap and expose `ADK::Tools::CheckJobStatusTool` so clients can poll for results using the `job_id` returned in the initial `:pending` response.

### 2.4 Server Setup with `fast-mcp`

The examples above show how to wrap ADK components and register them with a `FastMcp::Server` instance. How you *run* that server depends on your needs:

*   **STDIO:**
    *   Ideal for local tools, development, or integration with clients like Claude Desktop or `mcp-inspector` that manage the server process.
    *   Achieved by calling `mcp_server.start` at the end of your script, as shown in the examples.
    *   The script will block, listening on standard input/output.
*   **Rack Middleware:**
    *   Integrates the MCP server into an existing Ruby web application (Rails, Sinatra, etc.).
    *   Clients connect via HTTP/SSE to endpoints managed by the middleware (typically `/mcp/messages` and `/mcp/sse`).
    *   Use `FastMcp.rack_middleware` (or `FastMcp.authenticated_rack_middleware` for token auth) to create the middleware, passing your app and a block to configure the server and register tools.
    *   See the commented-out Rack example in Section 2.1 and the `fast-mcp` documentation for details on integrating the middleware.
*   Refer to the [`fast-mcp` README](https://github.com/yjacquin/fast-mcp) for more detailed setup instructions and options.

## 3. Schema Conversion Details

Automatic conversion happens between the different schema formats used by ADK, MCP, and `fast-mcp`. Understanding this is helpful when defining tools or troubleshooting.

**Formats:**

*   **ADK Parameters:** Defined within `ADK::Tool` using `define_metadata`. A Ruby hash like:
    ```ruby
    { 
      param_name: { 
        type: :symbol, # :string, :integer, :numeric, :boolean, :array, :hash 
        required: boolean, 
        description: string 
      }, 
      # ... 
    }
    ```
*   **MCP JSON Schema:** Standard JSON Schema objects used in MCP `tools/list` (`inputSchema`) and `resources/list` (`schema`).
    ```json
    { 
      "type": "object", 
      "properties": { 
        "param_name": { "type": "string", "description": "..." }
      },
      "required": ["param_name"]
    }
    ```
*   **Dry::Schema:** Used by `fast-mcp` within the `arguments` block to define and validate tool parameters.
    ```ruby
    arguments do
      required(:param_name).filled(:string).description("...")
    end
    ```

**Conversions:**

1.  **MCP JSON Schema -> ADK Params:**
    *   **Where:** Done by `ADK::Mcp::ToolWrapper.from_mcp_schema` using `ADK::Mcp::Util::SchemaConverter.json_to_adk`.
    *   **Use Case:** When an ADK Agent connects to an external MCP server and discovers its tools.
    *   **Mapping (V1):** Basic types (`string`, `integer`, `number`, `boolean`) are mapped to corresponding ADK types (`:string`, `:integer`, `:numeric`, `:boolean`). `required` status and `description` are preserved.
    *   **Limitations (V1):** Complex types (`object`, `array`), constraints (`minLength`, `enum`, `format` etc.) are **ignored** during conversion. Only the basic type, requirement, and description are used.

2.  **ADK Params -> Dry::Schema:**
    *   **Where:** Done by `ADK::Mcp::Server::AdkToolAdapter.wrap` using `ADK::Mcp::Util::SchemaConverter.adk_to_dry_schema`.
    *   **Use Case:** When exposing an `ADK::Tool` via `fast-mcp`.
    *   **Mapping (V1):** Basic ADK types (`:string`, `:integer`, `:numeric`, `:boolean`) are mapped to appropriate `Dry::Schema` calls (`filled(:string)`, `filled(:integer)`, `filled(Dry::Types['coercible.float'])`, `filled(:bool)`). `:required` status maps to `required()` or `optional()`.
    *   **Limitations (V1):** ADK types `:array`, `:hash`, `:object` receive basic mappings (`value(:array)`, `value(:hash)`) **without** nested schema validation. Parameter descriptions from ADK metadata are **not** added to the Dry::Schema block itself (they are set separately on the `fast-mcp` tool using `description` DSL by the adapter).

3.  **ADK Params -> JSON for MCP Call (Client):**
    *   **Where:** Inside `ADK::Mcp::ToolWrapper#perform_execution`.
    *   **Use Case:** When an ADK Agent executes an external MCP tool.
    *   **Mapping (V1):** Simple conversion of the ADK params hash (symbol keys) to a JSON hash (string keys). Assumes a flat structure.

**Key Takeaway:** For V1, schema conversion primarily supports basic data types and required fields. Complex nested structures or validation rules defined in one system may not be fully enforced or represented when crossing the ADK <-> MCP boundary.

## 4. Future Considerations

*   More robust schema conversion.
*   HTTP/SSE connection support for the ADK client.
*   Client authentication support.
*   Stateful agent adapter options.
*   MCP Resource support in ADK. 