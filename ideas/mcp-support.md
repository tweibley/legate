# PRD: Model Context Protocol (MCP) Support for adk-ruby

**Version:** 1.0
**Date:** 2025-04-17
**Status:** Draft
**Author:** AI Assistant based on user request

## 1. Introduction

### 1.1. Goals

*   **Enable Interoperability:** Allow `adk-ruby` agents to leverage tools and resources exposed by external MCP servers (acting as an MCP client).
*   **Expand Ecosystem:** Allow `adk-ruby` tools and agents to be exposed via the MCP standard, making them usable by other MCP-compliant clients (e.g., Claude Desktop, custom applications).
*   **Maintain Idiomatic Ruby:** Ensure that MCP integration feels natural within the existing `adk-ruby` framework structure and Ruby conventions.

### 1.2. Problem Statement

Currently, `adk-ruby` operates within its own ecosystem. Agents can only use tools defined within the `adk-ruby` framework (`ADK::Tool`). There is no standard mechanism to:
1.  Consume external tools/services that adhere to the MCP standard.
2.  Expose `adk-ruby` capabilities (tools or agent interactions) to external applications using the MCP standard.
This limits the potential reach and integration capabilities of agents built with `adk-ruby`.

### 1.3. Scope

*   **In Scope:**
    *   Implementing an MCP client component within `adk-ruby` to connect to and use external MCP servers (supporting STDIO and potentially HTTP/SSE transports).
    *   Implementing an adapter layer or providing mechanisms to expose existing `ADK::Tool` definitions via an MCP server (leveraging `fast-mcp` is recommended).
    *   *Experimental:* Defining a way to expose a complete `ADK::Agent` interaction flow as a single MCP tool.
    *   Schema conversion between `adk-ruby` tool metadata and MCP tool schemas.
*   **Out of Scope (for V1):**
    *   Implementing a full, standalone MCP server *natively* within `adk-ruby` (recommend leveraging `fast-mcp`).
    *   Full support for MCP Resource subscriptions and notifications within the *client* component (focus on tool usage first).
    *   Advanced MCP features not explicitly covered (e.g., complex capabilities negotiation).
    *   Built-in authentication handling *within the MCP client* (initial focus on unauthenticated or externally authenticated connections). Authentication for the *server* side would rely on `fast-mcp`'s features if used.

## 2. User Stories

*   **As a developer using `adk-ruby`:**
    *   I want to configure my `ADK::Agent` to connect to an external MCP server (e.g., a local filesystem server run via `npx`).
    *   I want my `ADK::Agent`'s planner to discover and list tools available from the connected MCP server alongside native `ADK::Tool`s.
    *   I want my `ADK::Agent` to be able to execute tools provided by the external MCP server as part of its plan.
*   **As a developer with existing `ADK::Tool`s:**
    *   I want to easily expose my `ADK::Tool`s (like `Calculator` or `CatFacts`) via an MCP server interface, using a library like `fast-mcp`.
    *   I want external MCP clients (like the MCP Inspector or Claude Desktop) to be able to discover and call my exposed `ADK::Tool`s.
*   **As a developer with a configured `ADK::Agent`:**
    *   I want to expose the functionality of my entire `ADK::Agent` as a single tool on an MCP server, allowing external clients to send a prompt and receive the agent's final response via an MCP `call_tool` request.

## 3. Functional Requirements

### 3.1. Using External MCP Tools (ADK as Client)

*   **FR1.1: MCP Client Component (`ADK::Mcp::Client` or `ADK::Mcp::Toolset`):**
    *   Implement a class responsible for managing the connection to and interaction with a single external MCP server.
    *   Must support connection via:
        *   STDIO (using `Open3` or similar for process management). Requires careful handling of stdin/stdout/stderr and process lifecycle.
        *   *(Optional V1.1)* HTTP/SSE (using `faraday` with an SSE adapter, or another suitable HTTP library).
    *   Implement methods corresponding to MCP client-side actions: `connect`, `disconnect`, `initialize_server`, `list_tools`, `call_tool`.
    *   Handle JSON-RPC 2.0 request/response formatting and ID correlation.
    *   Manage connection state (disconnected, connecting, connected, error).
*   **FR1.2: MCP Tool Representation (`ADK::Mcp::ToolWrapper`):**
    *   Define a class inheriting from `ADK::Tool` that acts as a proxy for a tool discovered on an external MCP server.
    *   `initialize`: Takes the MCP tool schema (name, description, inputSchema) and a reference to the `ADK::Mcp::Client`.
    *   `define_metadata`: Dynamically sets the tool's metadata (`name`, `description`, `parameters`) based on the received MCP schema. Requires conversion logic from JSON Schema (MCP) to `adk-ruby`'s parameter hash format.
    *   `perform_execution`: Takes the `params` hash, translates it to the arguments expected by the MCP tool, calls `client.call_tool`, receives the MCP result, and translates it back into the standard `adk-ruby` `{ status: :success/:error, ... }` hash format.
*   **FR1.3: Tool Discovery and Integration:**
    *   The `ADK::Mcp::Client`'s `list_tools` implementation should retrieve tools from the server and instantiate `ADK::Mcp::ToolWrapper` objects for each.
    *   Provide a mechanism for an `ADK::Agent` to be configured with an `ADK::Mcp::Client` instance.
    *   Modify `ADK::Agent` (or provide a helper) to include tools discovered via its associated MCP client(s) in the list of tools available to its `ADK::Planner`.
    *   The `ADK::Planner` must be able to correctly represent these proxied MCP tools in its prompts.
*   **FR1.4: Lifecycle Management:**
    *   Implement explicit `connect` and `disconnect` methods on the `ADK::Mcp::Client`.
    *   Ensure STDIO processes are properly terminated on disconnect or application exit. Consider using `at_exit` handlers or requiring manual cleanup.

### 3.2. Exposing ADK Tools via MCP (ADK as Server - Leveraging `fast-mcp`)

*   **FR2.1: ADK::Tool to FastMcp::Tool Adapter:**
    *   Provide a helper method, utility class, or a `FastMcp::Tool` subclass (`ADK::Mcp::Server::AdkToolWrapper`) that can take an *existing* `ADK::Tool` *class* (or instance) as input.
    *   **Schema Conversion:** This adapter must convert the `ADK::Tool`'s metadata (`define_metadata`) into the `Dry::Schema` structure expected by `fast-mcp`'s `arguments` block. This includes mapping parameter names, types (string, integer, float, boolean, array, hash - may need mapping), required status, and descriptions.
    *   **Call Handling:** The adapter's `call` method (required by `fast-mcp`) must:
        *   Instantiate the underlying `ADK::Tool`.
        *   Call the `ADK::Tool`'s `execute` method with the arguments received from `fast-mcp`.
        *   Translate the standard ADK result hash (`{ status: :success/:error, result/error_message: ... }`) into the format expected by MCP clients (typically a text or JSON string within the MCP response structure, potentially indicating errors).
*   **FR2.2: Integration with `fast-mcp` Server:**
    *   Provide clear documentation and potentially helper methods/Rake tasks showing how to instantiate a `FastMcp::Server` and register these adapted `ADK::Tool`s using `server.register_tool`.
    *   Include examples using both STDIO (`server.start`) and Rack (`FastMcp.rack_middleware`) transports provided by `fast-mcp`.

### 3.3. Exposing ADK Agents via MCP (Experimental)

*   **FR3.1: ADK::Agent to FastMcp::Tool Adapter (`ADK::Mcp::Server::AdkAgentWrapper`):**
    *   Define a new class inheriting from `FastMcp::Tool`.
    *   **Configuration:** The wrapper needs to be configured with the *name* of the target `ADK::Agent` definition (as stored in Redis) and access to an `ADK::SessionService` instance (likely Redis-based for persistence if needed across calls, or temporary in-memory).
    *   **Schema:** The MCP tool schema (`arguments` block) exposed by this wrapper should likely accept a single required string parameter (e.g., `prompt` or `user_input`).
    *   **Call Handling:** The wrapper's `call` method must:
        *   Receive the user `prompt` from the MCP client.
        *   **Session Management Challenge:** Determine the session strategy:
            *   *Option A (Stateless):* Create a *new*, temporary `ADK::Session` (using the configured `SessionService`) for *each* `call_tool` invocation. This loses conversation context between calls but is simpler.
            *   *Option B (Session ID via Args):* Require the MCP client to pass a `session_id` in the `call_tool` arguments. The wrapper uses `session_service.get_session` or `create_session`. This requires client cooperation.
            *   *Option C (External Mapping):* Assume an external layer maps MCP client identity to an ADK `session_id` (complex, likely out of scope for V1).
            *   **Recommendation V1:** Start with Option A (temporary session per call) for simplicity.
        *   Load the target `ADK::Agent` definition from Redis.
        *   Instantiate the `ADK::Agent` ephemerally (similar to `ADK::Tools::AgentTool`).
        *   Add configured tools to the ephemeral agent instance.
        *   Start the agent runtime.
        *   Call `agent.run_task(session_id: ..., user_input: prompt, session_service: ...)` using the chosen session strategy.
        *   Receive the final `ADK::Event` from `run_task`.
        *   Format the `event.content` (or error message) into an MCP-compliant response format (e.g., text content).
        *   Stop the ephemeral agent runtime.
        *   Clean up the session if temporary (Option A).
*   **FR3.2: Integration with `fast-mcp` Server:** Document how to register `ADK::Mcp::Server::AdkAgentWrapper` instances with a `FastMcp::Server`.

## 4. Non-Functional Requirements

*   **NFR1: Performance:** MCP interactions, especially schema conversions and process communication (STDIO), should have acceptable overhead. SSE connections should be handled efficiently.
*   **NFR2: Error Handling:** Robust handling of JSON parsing errors, connection errors (STDIO, SSE), process management errors, tool execution errors, and MCP protocol errors. Errors should be logged clearly and reported back via appropriate MCP error responses where applicable.
*   **NFR3: Security:**
    *   *(Client)* When connecting via HTTP/SSE, consider standard web security (TLS). Auth handling is initially out of scope but should be considered for future iterations.
    *   *(Server)* If using `fast-mcp`'s Rack transport, leverage its DNS rebinding protection and authentication options. Securely manage any API keys or credentials used by the exposed ADK tools.
*   **NFR4: Logging:** Integrate MCP client/server interactions with `ADK.logger`, providing useful debug information.
*   **NFR5: Documentation:** Clear documentation on how to configure and use both the client and server aspects of MCP integration, including examples. Document schema mapping between ADK and MCP.
*   **NFR6: Testing:** Add RSpec tests covering MCP client connection/interaction, schema conversion, tool proxying, and the server-side adapters.

## 5. Dependencies & External Factors

*   **External MCP Servers:** Availability and stability of external MCP servers for testing the client component (e.g., `@modelcontextprotocol/server-filesystem`). Requires `npx`.
*   **`fast-mcp` Gem:** Recommended dependency for implementing the server-side exposure of ADK components. Requires understanding its API (`FastMcp::Tool`, `FastMcp::Server`, `Dry::Schema`).
*   **Ruby Standard Libraries:** `json`, `open3` (for STDIO).
*   **Potential Gems:** HTTP client with SSE support (e.g., `faraday-sse`, `eventmachine`, or custom implementation), `dry-schema` (if adopting `fast-mcp` conventions).

## 6. Implementation Plan / Codebase Changes (`adk-ruby`)

### Phase 1: MCP Client Implementation

1.  **Create MCP Namespace:** Add `lib/adk/mcp/` directory.
2.  **Connection Management:**
    *   Create `lib/adk/mcp/connection/base.rb`, `stdio.rb`, `sse.rb` (optional). Define interface for `connect`, `disconnect`, `send_request`, `read_response`.
    *   Implement `StdioConnection` using `Open3.popen3` to manage the external `npx` process, handle pipes, and process lifecycle.
3.  **Client Logic:**
    *   Create `lib/adk/mcp/client.rb`.
    *   Implement methods: `initialize` (takes connection params), `connect`, `disconnect`, `request(method, params)`.
    *   Handle JSON-RPC formatting, request IDs, and response parsing/correlation.
    *   Implement specific MCP methods: `initialize_server`, `list_tools` (parses response), `call_tool`.
4.  **Tool Wrapper & Schema Conversion:**
    *   Create `lib/adk/mcp/tool_wrapper.rb` inheriting `ADK::Tool`.
    *   Implement `initialize` to store MCP schema and client reference.
    *   Implement `perform_execution` to call `client.call_tool` and translate results.
    *   Implement `self.from_mcp_schema` class method to handle conversion from MCP JSON Schema to `ADK::Tool` metadata format for `define_metadata`. This is the core translation logic.
5.  **Agent Integration:**
    *   Modify `ADK::Agent#initialize` or add a method like `add_mcp_client` to associate a client instance.
    *   Modify `ADK::Agent#tools` (or related method used by planner) to include tools fetched from associated MCP clients (`client.list_tools.map { |schema| ToolWrapper.from_mcp_schema(schema, client) }`).
    *   *(Low Priority)* Modify `ADK::Planner` if needed to better handle MCP tool descriptions/schemas.

### Phase 2: Exposing ADK Tools via MCP (using `fast-mcp`)

1.  **Create Server Adapter Namespace:** Add `lib/adk/mcp/server/` directory.
2.  **ADK -> Dry::Schema Conversion:**
    *   Create `lib/adk/mcp/server/schema_converter.rb`.
    *   Implement `convert(adk_metadata)` method to take `ADK::Tool` metadata hash and output a `Dry::Schema` definition block content (or dynamically create a schema object). Map types (e.g., `:string` -> `filled(:string)`).
3.  **ADK Tool Adapter for `fast-mcp`:**
    *   Create `lib/adk/mcp/server/adk_tool_adapter.rb` inheriting `FastMcp::Tool`.
    *   `initialize`: Takes an `ADK::Tool` class or instance.
    *   Implement `self.description`, `self.tool_name`, `self.arguments` by calling the `SchemaConverter` on the wrapped `ADK::Tool`'s metadata.
    *   Implement `call(**args)`: Instantiate the `ADK::Tool`, call `execute(args)`, translate the `{ status:, ...}` hash to an MCP response string/structure.
4.  **Documentation/Examples:** Provide examples showing how to:
    *   Instantiate `FastMcp::Server`.
    *   Create instances of `AdkToolAdapter` for existing `ADK::Tool`s.
    *   Register these adapters using `server.register_tool`.
    *   Run the server using `server.start` (STDIO) or `FastMcp.rack_middleware`.

### Phase 3: Exposing ADK Agents via MCP (Experimental)

1.  **Agent Adapter Tool:**
    *   Create `lib/adk/mcp/server/adk_agent_adapter.rb` inheriting `FastMcp::Tool`.
    *   `initialize`: Takes target agent name (string), `ADK::SessionService` instance.
    *   `self.arguments`: Define schema accepting `prompt: string` (and potentially optional `session_id: string` for Strategy B).
    *   `call(**args)`: Implement the logic described in FR3.1 (instantiate agent from Redis def, manage session, call `run_task`, format result).
2.  **Documentation:** Explain how to register and use this adapter, clearly stating the limitations regarding session management (recommend Strategy A initially).

## 7. Open Questions & Future Considerations

*   **Session Management for Exposed Agents:** How to best handle ADK session state when exposing an agent via the stateless MCP `call_tool` method? Strategy A (temp session) is simplest but loses context. Strategy B (session ID in args) requires client changes. This needs further investigation and clear documentation of the chosen approach and its trade-offs.
*   **MCP Resource Support (Client):** How deeply should the `adk-ruby` client support MCP resources (read, subscribe, notifications)? V1 focuses on tools.
*   **Authentication (Client):** When and how should the MCP client support authenticated connections (e.g., passing tokens for SSE/HTTP)?
*   **Error Granularity:** How to map detailed ADK tool errors or agent execution errors into the simpler MCP error structure?
*   **Long-Running Tools:** Can the MCP client (`ADK::Mcp::Client`) handle the multiple responses generated by a long-running MCP tool? How would that integrate with the `adk-ruby` agent's synchronous `execute_step` flow? This likely requires significant changes to `adk-ruby`'s core execution model, possibly linking to the separate "Long-Running Function Tool Support" PRD.
*   **Native MCP Server:** Is there a long-term need for a native MCP server within `adk-ruby` instead of relying on `fast-mcp`?