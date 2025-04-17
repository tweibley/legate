# ADK-Ruby: MCP Implementation Plan

**Version:** 1.0
**Date:** 2025-04-18
**Based On:** `ideas/mcp-support.md` PRD V1.0

## 1. Introduction

This document outlines the engineering plan for implementing Model Context Protocol (MCP) support within the `adk-ruby` library. The goal is to enable interoperability, allowing ADK agents to consume external MCP tools and exposing ADK tools/agents via MCP using the `fast-mcp` library.

This plan breaks the work into logical phases, detailing specific tasks, testing requirements, and key considerations.

## 2. Phases & Tasks

### Phase 0: Setup & Foundation

*   **Goal:** Establish the basic project structure and core utilities for MCP integration.
*   **Tasks:**
    *   **0.1:** Create directory structure: `lib/adk/mcp/`, `lib/adk/mcp/connection/`, `lib/adk/mcp/server/`, `lib/adk/mcp/util/` (or similar for utilities like schema conversion).
    *   **0.2:** Create initial files: `lib/adk/mcp.rb`, `lib/adk/mcp/error.rb` (for custom MCP-related errors).
    *   **0.3:** Implement basic JSON-RPC 2.0 request/response generation/parsing helpers if needed (e.g., in `lib/adk/mcp/util/json_rpc.rb`).
    *   **0.4:** Integrate `ADK.logger` into the MCP module structure for consistent logging. Add initial log points for module loading.
*   **Testing:** N/A (Setup phase).

### Phase 1: Schema Conversion Utilities

*   **Goal:** Implement the core logic for translating between MCP JSON Schema, ADK parameters, and Dry::Schema. Focus on basic types for V1.
*   **Tasks:**
    *   **1.1:** Implement `ADK::Mcp::Util::SchemaConverter.json_to_adk(json_schema_properties, json_schema_required_array)`:
        *   Input: MCP `inputSchema.properties` hash and `inputSchema.required` array.
        *   Output: ADK `parameters` hash (`{ param_name: { type: :symbol, required: boolean, description: string } }`).
        *   Handle types: `string`, `integer`, `number`, `boolean`.
        *   Handle `description` field.
        *   Determine `required` status.
        *   Log warnings/errors for unsupported types/structures (objects, arrays).
    *   **1.2:** Implement `ADK::Mcp::Util::SchemaConverter.adk_to_dry_schema(adk_parameters_hash)`:
        *   Input: ADK `parameters` hash.
        *   Output: A `Proc` or string representing the `Dry::Schema` block.
        *   Map ADK types (`:string`, `:integer`, `:numeric`, `:boolean`) to Dry::Schema types (`filled(:string)`, `filled(:integer)`, `filled(:float)`, `filled(:bool)`).
        *   Map `:required` to `required()`/`optional()`.
        *   Include descriptions using `.description()`.
        *   Log warnings/errors for unsupported ADK types (e.g., `:array`, `:hash` initially).
*   **Testing:**
    *   Unit tests for `SchemaConverter` covering all supported type mappings (both directions), required/optional status, descriptions, and handling of basic unsupported types.

### Phase 2: MCP Client Core Implementation

*   **Goal:** Implement the ability to connect to an external MCP server (via STDIO) and perform basic interactions.
*   **Tasks:**
    *   **2.1:** Implement `ADK::Mcp::Connection::Stdio`:
        *   Use `Open3.popen3` to manage the external process.
        *   Implement `connect(command, args)` method.
        *   Implement `disconnect` (terminate process, close streams).
        *   Implement `send_request(json_rpc_hash)` (write to process stdin).
        *   Implement `read_response_or_notification` (read from process stdout, handle potential blocking/timeouts, parse JSON).
        *   Handle stderr logging.
    *   **2.2:** Implement `ADK::Mcp::Client`:
        *   `initialize(connection_params)`: Store params for `StdioConnection`.
        *   `connect`: Create `StdioConnection`, call its `connect`, perform MCP `initialize` handshake (send request, validate response, store server capabilities).
        *   `disconnect`: Call `disconnect` on the connection.
        *   `list_tools`: Send `tools/list` request, parse response. Return array of MCP tool schema hashes.
        *   `call_tool(name, arguments)`: Build `tools/call` request, send, wait for/match response by ID, parse result or error. Handle JSON-RPC and MCP error responses gracefully.
*   **Testing:**
    *   Unit tests for `StdioConnection` (mocking `Open3`, testing process management, stream I/O).
    *   Unit tests for `Client` (mocking the `Connection` object, testing handshake logic, `list_tools`, `call_tool` request/response flows, error handling).

### Phase 3: Client Tool Integration

*   **Goal:** Allow ADK Agents to discover and execute tools from connected MCP servers.
*   **Tasks:**
    *   **3.1:** Implement `ADK::Mcp::ToolWrapper < ADK::Tool`:
        *   Implement `self.from_mcp_schema(mcp_schema_hash, mcp_client)`:
            *   Use `SchemaConverter.json_to_adk` to get ADK parameters.
            *   Dynamically define an anonymous class inheriting from `ToolWrapper`.
            *   Use `define_metadata` on the anonymous class.
            *   Store `mcp_client` and `mcp_tool_name` within the class/instance.
            *   Register the anonymous class with `ADK::ToolRegistry`.
        *   Implement `perform_execution(params, context)`:
            *   Translate ADK `params` back to simple JSON structure for `call_tool`. (Inverse of basic schema conversion).
            *   Call `mcp_client.call_tool`.
            *   Map MCP success/error responses to ADK status hashes (`{ status: :success, result: ... }` or `{ status: :error, error_message: ... }`).
    *   **3.2:** Modify `ADK::Agent`:
        *   Add mechanism to configure agent with MCP server connection details (e.g., `agent.add_mcp_server(type: :stdio, command: '...')`).
        *   On initialization or via the new method, create/store `ADK::Mcp::Client`, connect, call `list_tools`, and use `ToolWrapper.from_mcp_schema` to register tools in the agent's `ToolRegistry`.
    *   **3.3:** Ensure `ADK::Planner` correctly sees and can select the dynamically registered MCP tools.
*   **Testing:**
    *   Unit tests for `ToolWrapper.from_mcp_schema` (mocking client and converter).
    *   Unit tests for `ToolWrapper#perform_execution` (mocking client call and response mapping).
    *   Integration tests: Configure an `Agent` with a connection to a *real* external MCP server (e.g., `@modelcontextprotocol/server-filesystem`), verify tools are listed, and execute a simple wrapped tool.

### Phase 4: Server Adapter (Synchronous Tools)

*   **Goal:** Expose basic, synchronous ADK Tools via MCP using `fast-mcp`.
*   **Tasks:**
    *   **4.1:** Implement `ADK::Mcp::Server::AdkToolAdapter < FastMcp::Tool`:
        *   Implement `self.wrap(adk_tool_class)` class method:
            *   Retrieve metadata from `adk_tool_class`.
            *   Set `tool_name`, `description`.
            *   Use `SchemaConverter.adk_to_dry_schema` to generate the `arguments` block.
            *   Return a dynamically created subclass of `AdkToolAdapter`.
        *   Store the original `adk_tool_class` (e.g., in the generated subclass).
        *   Implement `call(**args)`:
            *   Instantiate the `adk_tool_class`.
            *   Create a dummy `ADK::ToolContext`.
            *   Call `adk_tool_instance.execute(args, dummy_context)`.
            *   Handle *only* `{ status: :success, result: res }` -> return `res`.
            *   Handle *only* `{ status: :error, error_message: msg }` -> raise `StandardError.new(msg)` or use `fast-mcp` error mechanism.
*   **Testing:**
    *   Unit tests for `AdkToolAdapter.wrap` (verify metadata, schema block generation).
    *   Unit tests for `AdkToolAdapter#call` (mocking ADK tool execution, testing success/error mapping for sync tools).
    *   Integration tests: Create a simple `fast-mcp` server instance, wrap a synchronous ADK tool (e.g., `EchoTool`), register it, and use an MCP client (e.g., `mcp-inspector` or even the client from Phase 3) to call it.

### Phase 5: Server Adapter (Asynchronous Tools)

*   **Goal:** Extend the server adapter to handle ADK's async tools (`:pending` status) and expose a way to check results.
*   **Tasks:**
    *   **5.1:** Modify `ADK::Mcp::Server::AdkToolAdapter#call`:
        *   Add handling for ADK result `{ status: :pending, job_id: jid, message: msg }`.
        *   Return a structured hash suitable for MCP clients (e.g., `{ "status": "pending", "job_id": jid, "message": msg || "Job submitted..." }`).
    *   **5.2:** Wrap `ADK::Tools::CheckJobStatusTool` using `AdkToolAdapter.wrap`. Ensure its schema is correctly generated.
    *   **5.3:** Update documentation and examples to show how to expose both an async tool and the `CheckJobStatusTool`.
*   **Testing:**
    *   Update unit tests for `AdkToolAdapter#call` to cover the `:pending` case.
    *   Update integration tests: Wrap an async ADK tool (e.g., `SleepyTool`) and `CheckJobStatusTool`. Use an MCP client to:
        *   Call the async tool, verify the pending response.
        *   Call `CheckJobStatusTool` with the `job_id`, verify the pending status initially.
        *   Wait, call `CheckJobStatusTool` again, verify the success/error status and final result.

### Phase 6: Server Agent Adapter (Experimental)

*   **Goal:** Provide a simple way to expose an entire ADK Agent as a single MCP tool.
*   **Tasks:**
    *   **6.1:** Implement `ADK::Mcp::Server::AdkAgentAdapter < FastMcp::Tool`:
        *   Implement `self.wrap(agent_definition_name, session_service_instance)`:
            *   Store `agent_definition_name`, `session_service_instance` (e.g., as class variables/config on the generated subclass).
            *   Set `tool_name`, `description`.
            *   Define `arguments` block for a single `prompt: :string`.
        *   Implement `call(prompt:)`:
            *   Implement Strategy A (Stateless): Create temp session, load agent def, instantiate agent, add tools, start agent, run task, stop agent, delete temp session, extract/return result.
            *   Map success/error/pending results appropriately (as per AdkToolAdapter).
*   **Testing:**
    *   Unit tests for `AdkAgentAdapter#call` (mocking agent loading, execution, session service).
    *   Integration tests: Configure `fast-mcp` with an agent adapter pointing to a defined agent (e.g., the `EchoAgent`). Use an MCP client to send a prompt and verify the response.

### Phase 7: Documentation & Refinement

*   **Goal:** Finalize documentation, add examples, and refine implementation details.
*   **Tasks:**
    *   **7.1:** Write comprehensive documentation for using the MCP client (`ADK::Agent` integration, connection options).
    *   **7.2:** Write comprehensive documentation for exposing tools/agents via `fast-mcp` (`AdkToolAdapter`, `AdkAgentAdapter`, schema conversion details).
    *   **7.3:** Create complete, runnable examples for both client and server scenarios.
    *   **7.4:** Refine error handling across all components based on testing and usage feedback. Ensure consistent error reporting.
    *   **7.5:** Review and enhance logging for clarity and debuggability.
    *   **7.6:** *(Optional)* Implement `ADK::Mcp::Connection::Sse` based on `StdioConnection` structure.
    *   **7.7:** *(Optional)* Enhance schema conversion to handle more complex types (arrays, simple objects) if deemed necessary.

## 3. Key Considerations

*   **Schema Conversion Limits (V1):** Initial conversion will only support basic JSON Schema types (string, number, integer, boolean) and ADK types (`:string`, `:numeric`, `:integer`, `:boolean`). Nested structures and arrays are out of scope for V1 conversion utilities. Robust error/warning messages for unsupported schemas are needed.
*   **Async Tool Exposure:** Handling the `:pending` status correctly on the server-side adapter and exposing `CheckJobStatusTool` are critical for making async ADK tools usable via MCP.
*   **Error Handling:** A consistent strategy is needed for mapping errors between ADK status hashes, JSON-RPC errors, MCP errors, and potential exceptions raised during execution.
*   **Dummy Context:** Server adapters will create a dummy `ADK::ToolContext`. This means context-dependent tool logic might not work as expected when exposed via MCP.
*   **Stateless Agent Adapter:** The initial agent adapter is stateless, creating a new session and agent instance per call. This is simpler but less efficient for conversational agents.
*   **Security:** The initial STDIO connection assumes a trusted local environment. `fast-mcp`'s security features should be leveraged for server exposure. Future HTTP/SSE connections would need TLS/auth considerations.

## 4. Dependencies

*   **`fast-mcp` gem:** Required for server-side adapters (Phase 4 onwards).
*   **`dry-schema` gem:** Indirect dependency via `fast-mcp`.
*   **External MCP Server:** Needed for client integration testing (Phase 3) (e.g., `@modelcontextprotocol/server-filesystem` via `npx`).
*   **Ruby Standard Libraries:** `open3`, `json`. 