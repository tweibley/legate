# PRD: Model Context Protocol (MCP) Support for adk-ruby

**Version:** 1.0
**Date:** 2025-04-17
**Status:** Draft

## 1. Introduction

### 1.1. Goals

*   **Enable Interoperability (Client):** Allow `adk-ruby` agents to discover and execute tools provided by external MCP servers, expanding their capabilities beyond natively defined `ADK::Tool`s.
*   **Expand Ecosystem (Server):** Provide a standardized way to expose `adk-ruby` tools (and potentially agents) via the MCP protocol, making them accessible to any MCP-compliant client (e.g., Claude Desktop, other agent frameworks, custom applications).
*   **Maintain Idiomatic Ruby:** Ensure that MCP integration feels natural within the existing `adk-ruby` framework structure and Ruby conventions.

### 1.2. Problem Statement

Currently, `adk-ruby` operates within its own tool ecosystem (`ADK::Tool`, `ADK::ToolRegistry`). Agents cannot easily utilize external tools or services that conform to the emerging MCP standard. Conversely, there is no standard way to make `adk-ruby`'s powerful tools or agent logic available to other systems that understand MCP. This limits the potential reach, composability, and integration capabilities of agents built with `adk-ruby`.

### 1.3. Proposed Solution

Integrate MCP support into `adk-ruby` through two primary mechanisms:

1.  **MCP Client Integration:** Implement functionality within `adk-ruby` to connect to external MCP servers (via STDIO or potentially HTTP/SSE), discover their tools, represent them as proxy `ADK::Tool` objects, and allow `ADK::Agent` instances to execute these proxy tools.
2.  **MCP Server Exposure (via `fast-mcp`):** Provide adapters and utilities to easily expose existing `ADK::Tool` definitions (and potentially `ADK::Agent` functionality) as tools on an MCP server implemented using the `fast-mcp` library.

### 1.4. Scope

*   **In Scope:**
    *   **MCP Client:**
        *   Connection management for external MCP servers (STDIO required, HTTP/SSE desirable).
        *   MCP methods: `initialize`, `tools/list`, `tools/call`.
        *   JSON-RPC 2.0 request/response handling.
        *   Proxy `ADK::Tool` (`ADK::Mcp::ToolWrapper`) representing an external MCP tool.
        *   Schema conversion from MCP JSON Schema to ADK parameter format.
        *   Integration with `ADK::Agent` and `ADK::Planner` for discovery and execution.
    *   **MCP Server Exposure (using `fast-mcp`):**
        *   Adapter (`ADK::Mcp::Server::AdkToolAdapter`) to wrap `ADK::Tool` classes for use with `fast-mcp`.
        *   Schema conversion from ADK parameter format to `Dry::Schema` (as required by `fast-mcp`).
        *   Adapter (`ADK::Mcp::Server::AdkAgentAdapter`) to expose an entire `ADK::Agent` (loaded from Redis definition) as a single `fast-mcp` tool (experimental).
    *   Documentation and examples for both client and server integration patterns.
*   **Out of Scope (for V1):**
    *   Implementing a full MCP server natively within `adk-ruby`.
    *   Full MCP Resource support (client-side `read`, `subscribe`; server-side exposure beyond basic examples).
    *   Client-side authentication support for connecting to secured MCP servers.
    *   Advanced MCP capabilities negotiation beyond basic initialization.
    *   Handling long-running tools exposed via MCP within the ADK client (requires rethinking ADK's synchronous tool execution).

## 2. User Stories

*   **As a developer using `adk-ruby`:**
    *   I want to configure my `ADK::Agent` with the connection details for an external MCP server (e.g., a local filesystem server run via `npx`, or a remote server via HTTP/SSE).
    *   I want my `ADK::Agent`'s planner to seamlessly discover and consider tools available from the connected MCP server alongside its native `ADK::Tool`s.
    *   I want my `ADK::Agent` to execute tools provided by the external MCP server as part of its generated plan, receiving results in the standard ADK format.
*   **As a developer with existing `ADK::Tool`s:**
    *   I want to easily expose my `ADK::Tool`s (like `Calculator`, `CatFacts`, `AgentTool`) via an MCP server interface implemented using `fast-mcp`.
    *   I want the parameter schemas defined in my `ADK::Tool` metadata to be automatically translated into the format required by `fast-mcp` and the MCP standard.
    *   I want external MCP clients (like the MCP Inspector or Claude Desktop) to be able to discover and successfully call my exposed `ADK::Tool`s.
*   **As a developer with a configured `ADK::Agent`:**
    *   I want to wrap my `ADK::Agent` (defined in Redis) and expose its conversational capability as a single, simple tool on a `fast-mcp` server.
    *   I want external MCP clients to be able to send a text prompt to this agent-tool and receive the agent's final processed response.

## 3. Functional Requirements

### 3.1. Using External MCP Tools (ADK as Client)

*   **FR1.1: MCP Connection Manager (`ADK::Mcp::Connection::Stdio` etc.):**
    *   Implement classes responsible for establishing and managing the low-level communication channel with an MCP server.
    *   **`StdioConnection`:** Must use `Open3.popen3` or similar to launch and manage an external command (e.g., `npx ...`). Handle reading from stdout, writing to stdin, error handling (stderr), and process termination.
    *   *(Optional V1.1)* `SseConnection`: Implement connection to a remote MCP server using HTTP Server-Sent Events for receiving messages and standard HTTP POST for sending requests. Use `faraday`, `net/http`, or a dedicated SSE client gem.
    *   Must provide methods like `connect`, `disconnect`, `send_request(json_rpc_hash)`, `read_response_or_notification`.
*   **FR1.2: MCP Client (`ADK::Mcp::Client`):**
    *   Coordinates interaction with an MCP server using a `Connection` instance.
    *   `initialize(connection_params)`: Takes parameters needed to establish the connection (e.g., command/args for STDIO, URL for SSE).
    *   `connect`: Establishes the connection and performs the MCP `initialize` handshake, storing server capabilities.
    *   `disconnect`: Closes the connection and cleans up resources (e.g., terminates STDIO process).
    *   `list_tools`: Sends `tools/list` request, receives response, parses MCP tool schemas. Returns an array of MCP schema hashes.
    *   `call_tool(name, arguments)`: Sends `tools/call` request, handles JSON-RPC request/response matching, returns the result payload from the server's response. Handles MCP error responses.
*   **FR1.3: MCP Tool Wrapper (`ADK::Mcp::ToolWrapper < ADK::Tool`):**
    *   Acts as an `ADK::Tool` proxy for an external MCP tool.
    *   `self.from_mcp_schema(mcp_schema_hash, mcp_client)`: Class method.
        *   Takes the MCP tool schema (name, description, inputSchema) and an `ADK::Mcp::Client` instance.
        *   **Schema Conversion (MCP JSON Schema -> ADK Params):** Translates the `inputSchema` (JSON Schema) into the `ADK::Tool` parameter hash format (`{ type: :symbol, required: boolean, description: string }`). Handle basic types (string, integer, number, boolean) and required fields. Nested objects/arrays are lower priority for V1 conversion.
        *   Dynamically defines a *new anonymous class* inheriting from `ToolWrapper`.
        *   Uses `define_metadata` on the anonymous class with the converted schema and the original MCP name/description.
        *   Stores the `mcp_client` reference and original `mcp_tool_name` in the anonymous class instance.
        *   Registers the anonymous class with `ADK::ToolRegistry` using the MCP tool name.
    *   `perform_execution(params, context)`:
        *   Translate the ADK `params` hash back into the JSON structure expected by the MCP tool based on its schema (simple key-value initially).
        *   Call `mcp_client.call_tool(mcp_tool_name, translated_args)`.
        *   Receive the MCP result. If it's an MCP error, return `{ status: :error, error_message: ... }`.
        *   If successful, attempt to parse the result (often text or JSON within the MCP response) and return `{ status: :success, result: ... }`. Handle potential parsing errors.
*   **FR1.4: Agent Integration:**
    *   Allow `ADK::Agent` to be configured with one or more `ADK::Mcp::Client` instances.
    *   Modify `ADK::Agent#initialize` or add `agent.add_mcp_server(connection_params)` which creates/stores a client, connects, calls `list_tools`, and uses `ToolWrapper.from_mcp_schema` to register the discovered tools with the `ADK::ToolRegistry`.
    *   Ensure `ADK::Planner` can access these dynamically registered tools via the registry for planning.
*   **FR1.5: Lifecycle:** Ensure MCP client connections are properly disconnected when the agent or application shuts down (e.g., via `at_exit` or explicit calls).

### 3.2. Exposing ADK Tools via MCP (using `fast-mcp`)

*   **FR2.1: Schema Converter Utility (`ADK::Mcp::Server::SchemaConverter`):**
    *   Implement `self.adk_to_dry_schema(adk_parameter_hash)`: Takes the `parameters` hash from `ADK::Tool.define_metadata`. Returns a block (`Proc` or string) containing the equivalent `Dry::Schema` definition for use in `fast-mcp`'s `arguments` block.
        *   Map ADK types (`:string`, `:integer`, `:numeric`, `:boolean`, etc.) to `Dry::Schema` types (`filled(:string)`, `filled(:integer)`, `filled(:float)`, `filled(:bool)`). Handle `:array`, `:hash` if possible (V1.1).
        *   Map `:required` status to `required()` or `optional()`.
        *   Include `.description()` calls using the ADK description.
*   **FR2.2: ADK Tool Adapter (`ADK::Mcp::Server::AdkToolAdapter < FastMcp::Tool`):**
    *   A class designed to be subclassed by users or used directly by wrapping an ADK Tool *class*.
    *   `self.wrap(adk_tool_class)`: A class method to dynamically create a subclass of `AdkToolAdapter`.
        *   It retrieves metadata from the `adk_tool_class`.
        *   Sets `description` using `adk_tool_class.description`.
        *   Sets `tool_name` using `adk_tool_class.tool_name`.
        *   Uses `SchemaConverter.adk_to_dry_schema` to generate the block for the `arguments` definition.
    *   `initialize`: Stores the original `adk_tool_class`.
    *   `call(**args)`:
        *   Instantiate the underlying `adk_tool_class`.
        *   **Context Handling:** Create a *dummy* `ADK::ToolContext` since there's no real ADK session in this context (pass nil or generic IDs).
        *   Call `adk_tool_instance.execute(args, dummy_context)`.
        *   Translate the resulting ADK hash:
            *   If `{ status: :success, result: res }`, return `res` (let `fast-mcp` handle formatting).
            *   If `{ status: :pending, job_id: jid }`, return a descriptive hash like `{ status: 'pending', job_id: jid, message: 'Job started...' }`.
            *   If `{ status: :error, error_message: msg }`, raise a `StandardError` with the `msg` (or return an error hash if `fast-mcp` has specific error handling).
*   **FR2.3: Documentation & Examples:**
    *   Provide clear examples using `fast-mcp`.
    *   Show how to instantiate `FastMcp::Server`.
    *   Show how to use `AdkToolAdapter.wrap(MyAdkTool)` or manual subclassing.
    *   Show how to register the adapter using `server.register_tool(MyAdaptedAdkTool)`.
    *   Provide examples for both STDIO (`server.start`) and Rack (`FastMcp.rack_middleware`) setups.

### 3.3. Exposing ADK Agents via MCP (Experimental)

*   **FR3.1: ADK Agent Adapter (`ADK::Mcp::Server::AdkAgentAdapter < FastMcp::Tool`):**
    *   `self.wrap(agent_definition_name, session_service_instance)`: Class method to create the adapter subclass. Store `agent_definition_name` and `session_service_instance`.
    *   `initialize`: No instance-specific state needed beyond class configuration.
    *   `self.tool_name`: Use the `agent_definition_name` or a derivative.
    *   `self.description`: Generate description like "Executes the ADK Agent: [agent_name]".
    *   `self.arguments`: Define a single required argument: `required(:prompt).filled(:string).description('The user input/prompt for the agent')`.
    *   `call(prompt:)`:
        *   Implement **Strategy A (Stateless):**
            *   Create a temporary session: `temp_session = @@session_service.create_session(app_name: @@agent_definition_name, user_id: 'mcp_user_temp')`. (Requires class variables set by `wrap`).
            *   Load agent definition from Redis using `@@agent_definition_name`.
            *   Instantiate `ADK::Agent` ephemerally. Add tools. Start agent.
            *   Execute: `event = agent.run_task(session_id: temp_session.id, user_input: prompt, session_service: @@session_service)`.
            *   Stop agent.
            *   Delete temporary session: `@@session_service.delete_session(session_id: temp_session.id)`.
            *   Extract result/error from `event.content`.
            *   Return result string/hash or raise error as per FR2.2.
*   **FR3.2: Documentation:** Provide example usage with `fast-mcp`, explaining the stateless nature of this initial implementation.

## 4. Non-Functional Requirements

*   **NFR1: Performance:** STDIO process communication and JSON-RPC overhead should be minimized. Schema conversions should be reasonably efficient.
*   **NFR2: Error Handling:** Graceful handling of connection failures, process termination, invalid JSON-RPC messages, MCP protocol errors, tool execution errors within wrappers. Clear logging of errors.
*   **NFR3: Security:** STDIO assumes a trusted local environment. HTTP/SSE client/server should consider TLS. Server exposure via `fast-mcp` should leverage its security features (Origin validation, auth).
*   **NFR4: Logging:** Integrate MCP client/server adapter interactions with `ADK.logger`. Log connection events, tool calls, schema conversions (debug), and errors.
*   **NFR5: Documentation:** Clear usage guides for both client-side consumption and server-side exposure. Document schema mapping rules. Provide complete examples.
*   **NFR6: Testing:** Comprehensive RSpec tests for connection classes, client logic, tool wrapper, schema converters, and server adapters. Integration tests using a sample external MCP server (e.g., filesystem server via `npx`) and the `fast-mcp` library.

## 5. Dependencies & External Factors

*   **External MCP Servers:** Need access to runnable MCP servers (like `@modelcontextprotocol/server-filesystem` via `npx`) for client testing.
*   **`fast-mcp` Gem:** Required dependency for the server-side exposure implementation.
*   **`dry-schema` Gem:** Required indirectly via `fast-mcp`.
*   **Ruby Standard Libraries:** `json`, `open3`.
*   **Potential Gems:** HTTP/SSE client library (e.g., `faraday` + adapter, `eventsource`).

## 6. Implementation Plan / Codebase Changes (`adk-ruby`)

*   **Phase 1: Core MCP Client:**
    *   Create `lib/adk/mcp/` structure.
    *   Implement `Connection::Stdio`.
    *   Implement `Client` basics (`connect`, `disconnect`, JSON-RPC handling, `initialize`).
    *   Implement `Client#list_tools`, `Client#call_tool`.
    *   Add basic tests for connection and client methods.
*   **Phase 2: Client Tool Integration:**
    *   Implement `Mcp::ToolWrapper` including `from_mcp_schema` (basic type conversion).
    *   Modify `Agent` to accept MCP clients and integrate tools into planner view.
    *   Add integration tests using an external MCP server (e.g., filesystem).
*   **Phase 3: Server Exposure (via `fast-mcp`):**
    *   Implement `Server::SchemaConverter` (ADK -> Dry::Schema).
    *   Implement `Server::AdkToolAdapter`.
    *   Add tests for the converter and adapter.
    *   Create documentation and examples using `fast-mcp`.
*   **Phase 4: Agent Exposure (Experimental):**
    *   Implement `Server::AdkAgentAdapter`.
    *   Add tests and documentation, highlighting limitations.
*   **Phase 5: Refinements:**
    *   *(Optional)* Implement `Connection::Sse`.
    *   Refine error handling and logging across all components.
    *   Improve schema conversion robustness (nested types, arrays).

## 7. Open Questions & Future Considerations

*   **Schema Conversion Complexity:** How robust does the MCP JSON Schema <-> ADK Params <-> Dry::Schema conversion need to be for V1? Handle basic types first.
*   **Error Mapping:** Define a clear strategy for mapping MCP error codes/messages to/from ADK error statuses/messages.
*   **Authentication (Client):** How will `adk-ruby` handle connecting to authenticated MCP servers in the future?
*   **Resource Support:** When and how to add support for MCP Resources beyond basic tool interaction.
*   **Long-Running Tools:** How does this integrate with potential native long-running tool support in ADK (e.g., via Temporal or Sidekiq)? Can an MCP tool call be long-running from the ADK agent's perspective?