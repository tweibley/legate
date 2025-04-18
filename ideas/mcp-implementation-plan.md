# ADK-Ruby: MCP Implementation Plan

**Version:** 1.2
**Date:** 2025-04-19
**Based On:** `ideas/mcp-support.md` PRD V1.0

## 1. Introduction

This document outlines the engineering plan for implementing Model Context Protocol (MCP) support within the `adk-ruby` library. The goal is to enable interoperability, allowing ADK agents to consume external MCP tools and exposing ADK tools/agents via MCP using the `fast-mcp` library.

This plan breaks the work into logical phases, detailing specific tasks, testing requirements, and key considerations.

## 2. Phases & Tasks

### Phase 0: Setup & Foundation

*   **Status:** DONE
*   **Goal:** Establish the basic project structure and core utilities for MCP integration.
*   **Tasks:**
    *   **0.1:** Create directory structure: `lib/adk/mcp/`, `lib/adk/mcp/connection/`, `lib/adk/mcp/server/`, `lib/adk/mcp/util/`. (DONE)
    *   **0.2:** Create initial files: `lib/adk/mcp.rb`, `lib/adk/mcp/error.rb`. (DONE)
    *   **0.3:** Implement basic JSON-RPC 2.0 request/response generation/parsing helpers. (DONE - Integrated into Client/Connection)
    *   **0.4:** Integrate `ADK.logger` into the MCP module structure. (DONE)
*   **Testing:** N/A (Setup phase).

### Phase 1: Schema Conversion Utilities

*   **Status:** DONE
*   **Goal:** Implement the core logic for translating between MCP JSON Schema, ADK parameters, and Dry::Schema. Focus on basic types for V1.
*   **Tasks:**
    *   **1.1:** Implement `ADK::Mcp::Util::SchemaConverter.json_to_adk`. (DONE)
        *   Handles types: `string`, `integer`, `number`, `boolean`.
        *   Handles `description` field.
        *   Determines `required` status.
        *   Logs warnings/errors for unsupported types/structures.
    *   **1.2:** Implement `ADK::Mcp::Util::SchemaConverter.adk_to_dry_schema`. (DONE - Descriptions handled by Adapter)
        *   Input: ADK `parameters` hash.
        *   Output: A `Proc` representing the `Dry::Schema` block.
        *   Map ADK types (`:string`, `:integer`, `:numeric`, `:boolean`) to Dry::Schema types.
        *   Map `:required` to `required()`/`optional()`.
        *   *Note: Descriptions are not included in the generated block; they are set using the `description` DSL method in the `AdkToolAdapter`.*
        *   Logs warnings/errors for unsupported ADK types.
*   **Testing:**
    *   Unit tests for `SchemaConverter`. (Covered by `spec/adk/mcp/util/schema_converter_spec.rb`)

### Phase 2: MCP Client Core Implementation

*   **Status:** DONE
*   **Goal:** Implement the ability to connect to an external MCP server (via STDIO and SSE) and perform basic interactions.
*   **Tasks:**
    *   **2.1:** Implement `ADK::Mcp::Connection::Stdio`. (DONE)
    *   **2.2:** Implement `ADK::Mcp::Client`. (DONE)
    *   **2.3:** Implement `ADK::Mcp::Connection::Sse`. (DONE)
*   **Testing:**
    *   Unit tests for `StdioConnection`. (Covered by `spec/adk/mcp/connection/stdio_spec.rb`)
    *   Unit tests for `SseConnection`. (Covered by `spec/adk/mcp/connection/sse_spec.rb` - *Needs verification*)
    *   Unit tests for `Client`. (Covered by `spec/adk/mcp/client_spec.rb`)

### Phase 3: Client Tool Integration

*   **Status:** Partially DONE (Requires Agent/Planner Integration)
*   **Goal:** Allow ADK Agents to discover and execute tools from connected MCP servers.
*   **Tasks:**
    *   **3.1:** Implement `ADK::Mcp::ToolWrapper < ADK::Tool`. (DONE)
    *   **3.2:** Modify `ADK::Agent`. (TODO)
        *   Add mechanism to configure agent with MCP server connection details (e.g., new initializer arg, dedicated method).
        *   On initialization or via a new method, create/store `ADK::Mcp::Client`, connect, call `list_tools`, and use `ToolWrapper.from_mcp_schema` to register tools in the agent's `ToolRegistry`.
    *   **3.3:** Ensure `ADK::Planner` correctly sees and can select the dynamically registered MCP tools. (TODO - depends on 3.2)
*   **Testing:**
    *   Unit tests for `ToolWrapper` implicitly covered via `client_spec.rb`.
    *   Agent/Planner integration tests needed. (TODO)

### Phase 4: Server Adapter (Synchronous Tools)

*   **Status:** DONE
*   **Goal:** Expose basic, synchronous ADK Tools via MCP using `fast-mcp`.
*   **Tasks:**
    *   **4.1:** Implement `ADK::Mcp::Server::AdkToolAdapter < FastMcp::Tool`. (DONE)
*   **Testing:**
    *   Unit tests for `AdkToolAdapter.wrap` and `AdkToolAdapter#call`. (Covered by `spec/adk/mcp/server/adk_tool_adapter_spec.rb`)
    *   Integration tests using `fast-mcp` and a client. (Manual testing likely done, could formalize).

### Phase 5: Server Adapter (Asynchronous Tools)

*   **Status:** Partially DONE (Requires CheckJobStatus Wrapping & Testing)
*   **Goal:** Extend the server adapter to handle ADK's async tools (`:pending` status) and expose a way to check results.
*   **Tasks:**
    *   **5.1:** Modify `ADK::Mcp::Server::AdkToolAdapter#call` to handle `:pending`. (DONE)
    *   **5.2:** Wrap `ADK::Tools::CheckJobStatusTool` using `AdkToolAdapter.wrap`. (TODO)
    *   **5.3:** Update documentation and examples for async tools. (TODO)
*   **Testing:**
    *   Unit tests for `AdkToolAdapter#call` cover `:pending`. (Covered by `spec/adk/mcp/server/adk_tool_adapter_spec.rb`)
    *   Integration tests for async flow needed. (TODO - depends on 5.2)

### Phase 6: Server Agent Adapter (Experimental)

*   **Status:** DONE
*   **Goal:** Provide a simple way to expose an entire ADK Agent as a single MCP tool.
*   **Tasks:**
    *   **6.1:** Implement `ADK::Mcp::Server::AdkAgentAdapter < FastMcp::Tool`. (DONE - `adk_agent_adapter.rb`)
        *   Implement `self.wrap`.
        *   Implement `call(prompt:)` using Strategy A (Stateless).
    *   *Note: `adk_direct_agent_adapter.rb` also exists; purpose/relation needs clarification.*
*   **Testing:**
    *   Unit tests for `AdkAgentAdapter#call`. (Covered by `spec/adk/mcp/server/adk_agent_adapter_spec.rb`)
    *   Integration tests using `fast-mcp` and a client. (Manual testing likely done, could formalize).

### Phase 7: Documentation & Refinement

*   **Status:** Partially DONE / TODO
*   **Goal:** Finalize documentation, add examples, and refine implementation details.
*   **Tasks:**
    *   **7.1:** Write comprehensive documentation for using the MCP client (including SSE). (TODO - Review/Expand `docs/mcp_integration.md`)
    *   **7.2:** Write comprehensive documentation for exposing tools/agents via `fast-mcp`. (TODO - Review/Expand `docs/mcp_integration.md`, `docs/mcp_server_example_setup.md`)
    *   **7.3:** Create complete, runnable examples for key scenarios (Agent integration, Async flow, SSE). (TODO - Review/Expand examples)
    *   **7.4:** Refine error handling across all components (Mapping ADK <-> MCP errors). (TODO - Review needed)
    *   **7.5:** Review and enhance logging for clarity and debuggability. (TODO - Review needed)
    *   **7.6:** *(Optional)* Enhance schema conversion to handle more complex types (e.g., arrays, nested objects). (TODO)
*   **Testing:** Good unit test coverage exists for implemented core components. Integration tests need expansion.

## 3. Key Considerations

*   **Schema Conversion Limits (V1):** Current conversion supports basic types only. Nested structures/arrays are basic mappings. Descriptions handled by adapter, not schema proc.
*   **Async Tool Exposure:** Handling `:pending` is implemented in the adapter. Exposing `CheckJobStatusTool` requires explicit wrapping (Task 5.2).
*   **Error Handling:** A consistent strategy is needed for mapping errors between ADK status hashes, JSON-RPC errors, MCP errors, and potential exceptions raised during execution. Review needed (Task 7.4).
*   **Dummy Context:** Server adapters will create a dummy `ADK::ToolContext`. This means context-dependent tool logic might not work as expected when exposed via MCP.
*   **Agent Adapter:** `adk_direct_agent_adapter.rb` file exists alongside `adk_agent_adapter.rb`. Purpose/relation needs clarification/documentation.
*   **Security:** The initial STDIO connection assumes a trusted local environment. SSE/HTTP connections may require TLS/auth considerations depending on deployment. `fast-mcp`'s security features should be leveraged for server exposure.

## 4. Dependencies

*   **`