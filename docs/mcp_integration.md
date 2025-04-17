# ADK-Ruby: Model Context Protocol (MCP) Integration

This document explains how to integrate `adk-ruby` with the Model Context Protocol (MCP) standard, enabling interoperability with external tools and servers.

## 1. Using External MCP Tools (ADK as Client)

You can configure an `ADK::Agent` to connect to an external MCP server (e.g., one run via `npx @modelcontextprotocol/server-filesystem`) and use the tools provided by that server alongside its native tools.

### 1.1 Configuration

When initializing your `ADK::Agent`, pass the `mcp_servers` option. Currently, only `:stdio` connections are supported.

```ruby
require 'adk'
require 'adk/mcp' # Ensure MCP modules are loaded

# Configuration for an MCP server running via STDIO
mcp_server_config = {
  type: :stdio,
  command: 'npx', # The command to run
  args: ['@modelcontextprotocol/server-filesystem', '--stdio'] # Arguments for the command
}

# Create the agent, passing the MCP server config
my_agent = ADK::Agent.new(
  name: 'mcp_client_agent',
  description: 'An agent that uses external MCP tools.',
  mcp_servers: [mcp_server_config] # Pass as an array
  # Add native tools here if needed: tools: [MyNativeTool.new]
)

# Start the agent runtime - this automatically connects to the MCP server
my_agent.start

# Now the agent's planner can see tools from the MCP server!
ADK.logger.info("Agent available tools: #{my_agent.available_tools_metadata.map { |t| t[:name] }}")

# Example: Run a task that might use an external tool
# session_service = ADK::SessionService::InMemory.new # Or Redis
# session = session_service.create_session(app_name: 'test', user_id: 'user1')
# final_event = my_agent.run_task(
#   session_id: session.id,
#   user_input: "Read the file 'my_document.txt' using the filesystem tool.",
#   session_service: session_service
# )
# ADK.logger.info("Agent Result: #{final_event.content}")

# Stop the agent runtime - this disconnects the MCP server
my_agent.stop
```

### 1.2 How it Works

1.  The `ADK::Agent` uses the `:mcp_servers` config to create `ADK::Mcp::Client` instances during `agent.start`.
2.  Each `Mcp::Client` connects to its server (e.g., launches the STDIO process) and performs the MCP `initialize` handshake.
3.  The client calls `tools/list` on the MCP server.
4.  For each tool schema received, `ADK::Mcp::ToolWrapper.from_mcp_schema` is called.
5.  This generates an anonymous `ADK::Tool` subclass that acts as a proxy.
6.  The proxy tool class is registered with the *agent's specific* `ToolRegistry` instance.
7.  When the `ADK::Planner` generates a plan, it considers both native tools and these registered MCP proxy tools.
8.  When an MCP proxy tool is executed, its `perform_execution` method calls `mcp_client.call_tool` to invoke the *actual* tool on the external server.
9.  Results or errors are translated back into the standard ADK format.

## 2. Exposing ADK Components via MCP (using `fast-mcp`)

You can make your custom `ADK::Tool`s (and experimentally, `ADK::Agent`s) available to external MCP clients by using the provided adapters with the `fast-mcp` Ruby gem.

**(Requires `fast-mcp` gem in your Gemfile, e.g., `gem 'fast-mcp', path: '../path/to/fast-mcp'`)**

### 2.1 Exposing ADK Tools

Use the `ADK::Mcp::Server::AdkToolAdapter.wrap` method to create a `fast-mcp` compatible tool class from your existing `ADK::Tool` subclass.

```ruby
require 'fast_mcp'
require 'adk'
require 'adk/mcp'
require 'adk/mcp/server/adk_tool_adapter'

# --- Define or require your ADK::Tool subclass ---
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
    a = params[:a]
    b = params[:b]
    case params[:op]
    when '+' then { status: :success, result: a + b }
    when '-' then { status: :success, result: a - b }
    when '*' then { status: :success, result: a * b }
    when '/' then { status: :success, result: b.zero? ? 'Error: Division by zero' : a / b }
    else { status: :error, error_message: "Unknown operation: #{params[:op]}" }
    end
  rescue StandardError => e
    { status: :error, error_message: "Calculation error: #{e.message}" }
  end
end
# --------------------------------------------------

# 1. Create the fast-mcp tool class by wrapping the ADK tool
AdaptedCalculatorTool = ADK::Mcp::Server::AdkToolAdapter.wrap(MyCalculatorTool)

# If you have an async ADK tool (e.g., SleepyTool returning :pending):
# require 'adk/tools/sleepy_tool' # Assuming this exists
# AdaptedSleepyTool = ADK::Mcp::Server::AdkToolAdapter.wrap(ADK::Tools::SleepyTool)

# IMPORTANT: You also need to wrap the CheckJobStatusTool for async tools
# require 'adk/tools/check_job_status_tool'
# AdaptedCheckJobStatusTool = ADK::Mcp::Server::AdkToolAdapter.wrap(ADK::Tools::CheckJobStatusTool)

# 2. Create and configure the fast-mcp server
# Example using STDIO server:
mcp_server = FastMcp::Server::Stdio.new(
  server_info: { name: 'ADK Tool Server', version: '1.0' },
  logger: ADK.logger # Use ADK logger
)

# 3. Register the adapted tool(s)
mcp_server.register_tool(AdaptedCalculatorTool)
# mcp_server.register_tool(AdaptedSleepyTool)
# mcp_server.register_tool(AdaptedCheckJobStatusTool)

# 4. Start the server (this will block for STDIO)
puts "Starting ADK MCP Tool Server via STDIO..."
mcp_server.start

# To run as a Rack app instead:
# middleware = FastMcp.rack_middleware(
#   server_info: { name: 'ADK Tool Server', version: '1.0' },
#   logger: ADK.logger
# ) do |server|
#   server.register_tool(AdaptedCalculatorTool)
# end
# Run middleware with Rack::Builder or Sinatra, etc.

```

### 2.2 Exposing ADK Agents (Experimental)

You can wrap an agent definition stored in Redis as a single MCP tool.

**Prerequisites:**
*   An agent definition must exist in Redis (e.g., created via `adk agent create ...`).
*   A configured `ADK::SessionService` instance (e.g., `InMemory` or `Redis`) is required.

```ruby
require 'fast_mcp'
require 'adk'
require 'adk/mcp'
require 'adk/mcp/server/adk_agent_adapter'
require 'adk/session_service/in_memory' # Or redis

# Agent name as defined in Redis
AGENT_NAME_IN_REDIS = 'my_chat_agent' # Replace with your agent name

# Session service instance needed for temporary sessions
# Using InMemory for this example
session_service = ADK::SessionService::InMemory.new

# 1. Create the fast-mcp tool class by wrapping the agent definition
begin
  AdaptedAgentTool = ADK::Mcp::Server::AdkAgentAdapter.wrap(AGENT_NAME_IN_REDIS, session_service)
rescue ADK::Mcp::Error => e
  puts "Error wrapping agent: #{e.message}. Is Redis running and agent defined?"
  exit(1)
rescue StandardError => e
  puts "Unexpected error during wrap: #{e.message}"
  exit(1)
end

# 2. Create and configure the fast-mcp server
mcp_server = FastMcp::Server::Stdio.new(
  server_info: { name: 'ADK Agent Server', version: '1.0' },
  logger: ADK.logger
)

# 3. Register the adapted agent tool
mcp_server.register_tool(AdaptedAgentTool)

# 4. Start the server
puts "Starting ADK MCP Agent Server ('#{AGENT_NAME_IN_REDIS}') via STDIO..."
mcp_server.start
```

**Limitations (Agent Adapter V1):**
*   **Stateless:** Each `call` loads the agent definition, creates a temporary session, runs the task, and deletes the session. There is no conversation history between calls.
*   **Redis Dependency:** Requires Redis connection to load the agent definition on every call.
*   **Tool Loading:** Assumes tools defined for the agent in Redis exist in the global `ADK::ToolRegistry` when the adapter runs.

## 3. Next Steps & Future Considerations

*   **Testing:** Add integration tests for client-server interactions.
*   **Error Handling:** Refine error mapping between ADK and MCP.
*   **Schema Conversion:** Enhance `SchemaConverter` to support more complex types (arrays, objects).
*   **Authentication:** Add client support for connecting to secured MCP servers.
*   **HTTP/SSE:** Implement client/server support for HTTP/SSE connections.
*   **Resources:** Explore MCP Resource support.
*   **Agent Adapter State:** Investigate stateful options for the agent adapter. 