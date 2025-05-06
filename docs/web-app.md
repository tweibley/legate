# ADK Web Application Documentation

## Overview

The ADK Web Application provides a web-based user interface for managing and interacting with ADK (Agent Development Kit) Agents. It allows users to define, configure, run, and communicate with agents built using the ADK framework.

Key technologies used:

*   **Backend:** Ruby, Sinatra
*   **Frontend:** Slim (templating), Sass/CSS (styling), HTMX (dynamic UI updates without full page reloads)
*   **Persistence:** Redis (for agent definitions)
*   **Agent Communication:** ADK Core library, Gemini AI API, MCP (Multi-Capability Protocol) for external tools

## Features

*   **Agent Definition Management:**
    *   Create new agent definitions, specifying name, description, LLM model, tools, fallback behavior, and MCP server configurations.
    *   View a list of all defined agents and their current runtime status (Running/Stopped).
    *   View detailed information about a specific agent, including its configuration and available tools (native and MCP).
    *   Edit agent definitions inline (description, model, tools, fallback mode, MCP config) with automatic restart of running agents upon configuration change.
    *   Delete agent definitions. Agent definitions are persisted in Redis.
*   **Agent Runtime Management:**
    *   Start agent instances based on their stored definitions. Running instances are held in memory.
    *   Stop running agent instances.
*   **Agent Interaction:**
    *   **Chat Interface:** Engage in conversations with running agents. Session management preserves conversation history.
    *   **Direct Task Execution:** Submit tasks to agents via JSON input on the agent detail page. Supports both natural language tasks (using the agent's planner) and direct execution of specific tools with parameters.
    *   **Example Task Generation:** Generate example JSON task structures using the Gemini API based on the agent's configured tools, suitable for use in direct execution.
*   **Tool Management:**
    *   Leverages the `ADK::GlobalToolManager` to discover native tools defined within the ADK project.
    *   Connects to external MCP (Multi-Capability Protocol) servers specified in agent configurations to discover and utilize remote tools.
    *   Displays combined list of available native and MCP tools.
    *   Automatically includes the `check_job_status` tool for agents configured with asynchronous tools.
*   **Configuration:**
    *   Uses Redis for persisting agent definitions (requires a running Redis server).
    *   Requires `GOOGLE_API_KEY` environment variable for example task generation via Gemini API.
    *   Uses Sinatra sessions with a configurable `SESSION_SECRET`.
*   **Dynamic UI:**
    *   Uses HTMX extensively to update parts of the UI dynamically (e.g., agent status, adding/deleting agents, editing fields, chat messages, execution results) without requiring full page reloads.

## Setup and Configuration

1.  **Dependencies:** Ensure Ruby and Bundler are installed. Run `bundle install` to install required gems (Sinatra, Redis, etc.).
2.  **Redis:** A running Redis server is required for agent definition persistence. By default, the application attempts to connect to `localhost:6379`. Configure connection details if necessary (not directly exposed via ENV vars in current implementation, requires code change or Redis configuration).
3.  **Environment Variables:**
    *   `SESSION_SECRET`: (Recommended for production) A strong secret key for encrypting Sinatra session data. If not set, a temporary secret is generated on startup.
    *   `GOOGLE_API_KEY`: (Required for Example Task Generation feature) Your Google AI API key for interacting with the Gemini API.
    *   *(Optional)* Standard Redis environment variables (`REDIS_URL`, etc.) might be respected by the `redis` gem depending on its version and configuration.
4.  **Running the App:** Use `rackup` or `rerun rackup` (for development with auto-reloading) in the project's root directory.

## Key Concepts

*   **Agent Definition vs. Runtime:**
    *   **Definition:** The configuration of an agent (name, description, tools, model, MCP servers, fallback mode) stored persistently as a hash in Redis.
    *   **Runtime:** An active `ADK::Agent` object instance running in the web server's memory (`@agents` hash). Runtime instances are created based on definitions when an agent is started. Configuration changes require restarting the runtime instance.
*   **Redis Usage:**
    *   `adk:agents:all_names` (Set): Stores the names of all defined agents.
    *   `adk:agent:<agent_name>` (Hash): Stores the definition fields for a specific agent.
*   **HTMX:** A JavaScript library enabling AJAX requests, CSS transitions, WebSockets, and Server Sent Events directly in HTML using attributes (`hx-get`, `hx-post`, `hx-target`, `hx-swap`, `hx-swap-oob`, etc.). This is used extensively for dynamic updates without writing custom JavaScript.
    *   **OOB (Out of Band) Swaps:** Used to update multiple independent parts of the page from a single server response (e.g., updating agent status *and* enabling/disabling buttons simultaneously).
*   **MCP (Multi-Capability Protocol):** A protocol allowing the ADK agent to discover and interact with tools running as separate processes or on remote servers. The web app fetches tool lists from configured MCP servers to display them and allow their selection for agents.
*   **Session Management (Chat):**
    *   Uses standard Sinatra sessions (`enable :sessions`) to store a user's specific ADK session ID (`adk_session_id`) in a browser cookie.
    *   Uses an `ADK::SessionService` instance (`@session_service`, default in-memory) to store the actual conversation history (events) associated with that ID.
    *   Ensures chat continuity across requests for a specific user and agent. Temporary sessions are used for direct `/execute` calls.
*   **Helper Methods:** Utility functions defined within the `helpers do ... end` block, accessible in routes and Slim templates (e.g., `fetch_mcp_tools`, `format_execution_result_html`, `pretty_json`).

## Routes

*(Note: Routes often return HTML fragments intended for HTMX swaps rather than full pages.)*
*(Internally, these routes are organized into distinct modules within `lib/adk/web/routes/` and registered with the main Sinatra application in `lib/adk/web/app.rb` for better maintainability.)*

### General

*   `GET /`
    *   **Description:** Renders the main index/welcome page (`views/index.slim`).
*   `GET /healthz`
    *   **Description:** Health check endpoint. Pings Redis (if available).
    *   **Response:** `200 OK` (text body "OK") on success, `503 Service Unavailable` on failure.

### Agent Definition Management (Redis Persistence)

*   `GET /agents`
    *   **Description:** Displays the main agent management page (`views/agents.slim`), listing all defined agents, their status, and a form to create new agents. Fetches data from Redis.
*   `POST /agents`
    *   **Description:** Creates a new agent definition in Redis based on submitted form data. Validates input and MCP JSON.
    *   **Request Body:** Form data (`name`, `description`, `tools[]`, `model`, `fallback_mode`, `mcp_servers_json`).
    *   **Response:** HTML fragment for the new agent row (`_agent_row.slim`) and an OOB swap fragment to remove the "no agents" message. Targets the agent table body via HTMX.
*   `DELETE /agents/:name`
    *   **Description:** Deletes an agent definition from Redis. Stops the agent if it's currently running.
    *   **Response:** `200 OK` with an empty body (triggers HTMX row removal on the frontend).
*   `GET /agents/:name`
    *   **Description:** Displays the detail page (`views/agent.slim`) for a specific agent. Fetches definition from Redis, gets available native & MCP tools, filters by agent config, and displays details.
*   `GET /agents/:name/edit/:field`
    *   **Description:** Renders an inline edit form partial (`_edit_agent_*.slim`) for a specific field (`description`, `model`, `tools`, `fallback`, `mcp`). Fetches current value from Redis.
    *   **Response:** HTML fragment containing the edit form.
*   `GET /agents/:name/display/:field`
    *   **Description:** Renders a display partial (`_display_agent_*.slim`) for a specific field. Used by the "Cancel" button in edit forms (except 'tools').
    *   **Response:** HTML fragment showing the current value of the field.
*   `GET /agents/:name/display/tool_table`
    *   **Description:** Renders the full tool table display partial (`_agent_tool_table.slim`). Used by the "Cancel" button in the 'tools' edit view. Fetches agent definition and tool metadata.
    *   **Response:** HTML fragment containing the formatted tool table.
*   `PUT /agents/:name/update/:field`
    *   **Description:** Updates a specific field (`description`, `model`, `tools`, `fallback_mode`, `mcp_servers_json`) for an agent definition in Redis. Validates input. **Crucially, automatically stops and restarts the agent if it was running.**
    *   **Request Body:** Form data (`value` or `tools[]`).
    *   **Response:** HTML fragment displaying the updated field/tool table (`_display_agent_*.slim` or `_agent_tool_table.slim`). May include `HX-Trigger-After-Swap` header (`showRestartToast` or `showRestartErrorToast`) if an auto-restart occurred.

### Agent Runtime Management (In-Memory Instances)

*   `POST /agents/:name/start`
    *   **Description:** Starts a runtime instance of the agent (used by the main agent list). Calls `_start_agent`.
    *   **Response:** HTML fragments for status/button updates (`agent_status_fragments`) via HTMX OOB swap.
*   `POST /agents/:name/start/detail`
    *   **Description:** Starts a runtime instance of the agent (used by the agent detail page). Calls `_start_agent`.
    *   **Response:** HTML fragment for status controls (`_agent_status_controls.slim`) and an OOB swap fragment to update the "Execute Task" button state.
*   `POST /agents/:name/stop`
    *   **Description:** Stops a running agent instance (used by the main agent list). Calls `_stop_agent`.
    *   **Response:** HTML fragments for status/button updates (`agent_status_fragments`) via HTMX OOB swap.
*   `POST /agents/:name/stop/detail`
    *   **Description:** Stops a running agent instance (used by the agent detail page). Calls `_stop_agent`.
    *   **Response:** HTML fragment for status controls (`_agent_status_controls.slim`) and an OOB swap fragment to update the "Execute Task" button state.

### Agent Interaction

*   `GET /agents/:name/chat`
    *   **Description:** Renders the chat interface page (`views/chat.slim`). Requires the agent to be running. Manages/creates the ADK session and loads chat history.
*   `POST /agents/:name/chat`
    *   **Description:** Processes a user message from the chat input. Requires agent to be running and a valid session. Calls the agent's `run_task` method with session context.
    *   **Request Body:** Form data (`message`).
    *   **Response:** HTML fragment (`_chat_message.slim`) containing the user message and the agent's response, intended to be appended to the chat log via HTMX.
*   `POST /agents/:name/execute`
    *   **Description:** Executes a task directly, bypassing the chat UI. Requires agent to be running. Supports planner-based execution (`{"task": "..."}`) or direct tool execution (`{"tool_name": "...", "task": "...", "parameters": {...}}`). Uses a temporary session.
    *   **Request Body:** Form data (`task_json`).
    *   **Response (Success):** `200 OK` with HTML body containing the formatted execution result (`format_execution_result_html`). Target element is updated via HTMX.
    *   **Response (Error):** `200 OK` with JSON body `{"error": "..."}`. `HX-Trigger-After-Swap` header (`showTaskError` or `showTaskServerError`) triggers a frontend notification.
*   `GET /agents/:name/generate_example_task`
    *   **Description:** Generates an example JSON task based on the agent's configured tools using the Gemini API. Fetches agent config (model, tools, MCP) from Redis.
    *   **Response (Success):** `200 OK` with JSON body containing the pretty-printed example task object (`{"tool_name": ..., "task": ..., "parameters": ...}`).
    *   **Response (Error):** `404 Not Found` (if agent missing), `503 Service Unavailable` (if Redis/API key missing/API error), `500 Internal Server Error` (if JSON generation/parsing fails). Response body is JSON `{"error": "..."}`.

### API Endpoints (JSON)

*   `GET /api/agents`
    *   **Description:** Returns a JSON list of all defined agents, their description, configured model, and current running status.
    *   **Response:** JSON `{"agents": [...]}`.
*   `GET /api/tools`
    *   **Description:** Returns a JSON list of all available *native* tools known to the `ADK::GlobalToolManager`, including their metadata (name, description, parameters).
    *   **Response:** JSON `{"tools": [...]}`. 