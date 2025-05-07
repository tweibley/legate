# ADK Web UI: MCP Integration Plan

This document outlines the plan for integrating Model Context Protocol (MCP) server configuration and tool discovery/listing into the `adk-ruby` web UI (`lib/adk/web/app.rb`).

## 1. Storing MCP Configuration

*   **Redis Field:**
    *   Add a new field to the agent's Redis Hash for storing MCP server configurations.
    *   Suggested field name: `mcp_servers_json`.
*   **Format:**
    *   Store the configurations as a JSON string representing an array of MCP server configuration hashes (e.g., `[{ "type": "stdio", "command": "...", "args": [...] }]`).
*   **Helper Updates:**
    *   Modify existing helper methods in `app.rb` (e.g., `load_agent_definition`, `save_agent_definition`, or logic within routes) to read and write the `mcp_servers_json` field.
    *   Saving: Convert the Ruby array/hash structure to a JSON string.
    *   Loading: Parse the JSON string back into Ruby objects, handling potential `nil` values and `JSON::ParserError`.

## 2. Updating the UI for Configuration

*   **Forms:**
    *   Modify the agent creation form (`views/new_agent.erb`).
    *   Modify the agent editing form (`views/edit_agent.erb`).
*   **Input Method:**
    *   **(Initial)** Add a `<textarea name="mcp_servers_json">` to the forms for direct JSON input/editing. Provide placeholder text or examples.
    *   **(Future)** Consider a JavaScript-based UI for dynamic addition/editing of server configurations.
*   **Route Handling (Save/Update):**
    *   Update the `POST /agents` and `POST /agents/:name` (or relevant PUT route) in `app.rb`.
    *   Retrieve the `mcp_servers_json` string from form parameters.
    *   **Validate:**
        *   Attempt `JSON.parse`. Catch `JSON::ParserError` and return a user-friendly error (e.g., via flash message).
        *   Ensure the parsed result is an `Array`.
        *   (Optional) Add basic structural validation (e.g., each element is a Hash with a `type` key).
    *   Store the validated JSON string in the `mcp_servers_json` field in Redis.

## 3. Discovering and Listing MCP Tools

*   **Challenge:** Synchronously connecting to and listing tools from external MCP servers within a web request can block the UI and lead to timeouts.
*   **Recommended Approach (Synchronous with Timeouts):**
    1.  **Helper Method:** Create `fetch_mcp_tools(mcp_configs, timeout_seconds = 10)` in `app.rb`.
    2.  **Helper Logic:**
        *   Initialize an empty list for aggregated results.
        *   Iterate through `mcp_configs` (Ruby array parsed from JSON).
        *   For each `config`:
            *   Wrap the following in `Timeout.timeout(timeout_seconds)`.
            *   Create `ADK::Mcp::Client.new(config)`.
            *   Call `client.connect`.
            *   Call `client.list_tools`.
            *   **Immediately call `client.disconnect`.**
            *   Add the successfully fetched tools (array of hashes) to the aggregated results.
            *   Rescue `Timeout::Error`, `ADK::Mcp::ConnectionError`, `ADK::Mcp::ProtocolError`, and other relevant standard errors.
            *   On error, log it and add an error indicator to the results (e.g., `{ error: true, server_config: config, message: "Connection timed out" }`).
        *   Return the aggregated list containing tool arrays and/or error indicators.
    3.  **Route Handling (View):** In `GET /agents/:name`:
        *   Load agent definition, parse `mcp_servers_json`.
        *   Call `fetch_mcp_tools` with the parsed configs.
        *   Get native tools list (existing logic).
        *   Pass both lists (native tools, aggregated MCP results) to the view.
*   **Alternative (Asynchronous):**
    *   Use background jobs (e.g., Sidekiq) triggered on agent save.
    *   Job connects, lists tools, and saves the results (or errors) to a separate Redis key.
    *   Web view reads the cached list/errors. (More complex setup).

## 4. Updating the UI for Display

*   **Agent Detail View (`views/agent_detail.erb`):**
    *   Add a new section titled "MCP Tools" or similar.
    *   Iterate through the aggregated MCP results passed from the route.
    *   **For successful results:** Display the list of tools (name, description, parameters) similar to native tools. Clearly indicate which server they came from if multiple servers are configured.
    *   **For error indicators:** Display a clear error message indicating which server configuration failed and why (e.g., "Failed to fetch tools from server with command '...': Connection timed out").
    *   Ensure styling clearly distinguishes native and MCP tools.

## 5. Implementation Steps Summary

1.  Modify Redis load/save helpers to handle `mcp_servers_json`.
2.  Add `<textarea name="mcp_servers_json">` to `new_agent.erb` and `edit_agent.erb`.
3.  Update `POST /agents` and agent update routes to parse, validate, and save `mcp_servers_json`.
4.  Implement the `fetch_mcp_tools` helper method with connection/listing/disconnect logic and timeouts.
5.  Update `GET /agents/:name` route to call `fetch_mcp_tools` and pass results to the view.
6.  Update `views/agent_detail.erb` to display native tools, MCP tools, and any fetching errors. 