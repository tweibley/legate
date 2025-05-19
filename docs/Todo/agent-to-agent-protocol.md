Integrating A2A into `adk-ruby` would be a significant undertaking but also a massive enhancement, opening up a standardized way for your Ruby agents to interoperate with a wider ecosystem of AI agents.

Here's a breakdown of how we could approach this, thinking carefully about the ADK's current structure and the A2A spec:

**I. Core Concepts & Goals for ADK-Ruby A2A Support**

1.  **Act as an A2A Provider (Server-Side):** Allow an ADK agent to be exposed as an A2A-compliant service. This means handling incoming A2A requests (like `tasks/send`, `tasks/get`) and responding according to the A2A protocol.
2.  **Act as an A2A Consumer (Client-Side):** Allow an ADK agent to discover and interact with external A2A-compliant agents. This would likely involve a new type of "A2A Tool" within ADK.
3.  **Leverage Existing ADK Components:** Utilize `ADK::Agent`, `ADK::SessionService`, `ADK::Event`, `ADK::Tool`, etc., as much as possible.
4.  **Data Mapping:** Handle the translation between ADK's internal event/data structures and the A2A protocol's `Message`, `Part`, and `Artifact` structures.
5.  **Capabilities Negotiation:** Respect the `AgentCapabilities` in the `AgentCard`.

**II. Implementing A2A Provider (Server-Side)**

This means making an `ADK::Agent` (or a specific "skill" of it) accessible via an HTTP endpoint that speaks A2A JSON-RPC.

**A. New A2A Request Handler (Sinatra/Rack based)**

*   **Location:** Could be a new Sinatra application/module, similar to `ADK::Web::WebhookListener`, or integrated into `ADK::Web::App` under a specific base path (e.g., `/a2a/v1/`).
*   **Responsibilities:**
    1.  **Endpoint Definition:** Define HTTP POST endpoints for each A2A method (e.g., `/tasks/send`, `/tasks/get`, `/tasks/cancel`).
    2.  **JSON-RPC 2.0 Parsing:** Parse incoming JSON-RPC requests. Validate `jsonrpc: "2.0"`, `method`, `params`, `id`.
    3.  **Authentication Handling:**
        *   Inspect `Authorization` headers or other A2A-defined auth mechanisms.
        *   Needs integration with a new ADK authentication/authorization layer (see below).
    4.  **Method Dispatching:** Route requests to appropriate handlers based on the `method` field.
    5.  **Response Formatting:** Format responses according to JSON-RPC 2.0 (with `result` or `error` objects matching A2A error schemas).

**B. Agent Card Generation**

*   **Static or Dynamic:** An endpoint (e.g., `GET /agent-card`) should return the `AgentCard` JSON for the ADK agent being exposed.
*   **Mapping `ADK::AgentDefinition` to `AgentCard`:**
    *   `name`: From `AgentDefinition.name`.
    *   `description`: From `AgentDefinition.description`.
    *   `url`: The base URL where this A2A service is hosted.
    *   `provider`: Configurable globally or per-agent (organization name/URL).
    *   `version`: ADK version or a specific agent version.
    *   `capabilities`:
        *   `streaming`: Would require SSE/WebSocket support in the A2A handler.
        *   `pushNotifications`: Would require implementing the `/tasks/pushNotification/set` and `/tasks/pushNotification/get` methods and a way for the agent to send notifications.
        *   `stateTransitionHistory`: ADK sessions already store history. This capability could be `true`.
    *   `authentication`: Define supported schemes (e.g., "Bearer", "ApiKey").
    *   `skills`:
        *   This is crucial. How do ADK's "tools" or general agent capabilities map to A2A "skills"?
            *   **Option 1 (Agent-as-a-Skill):** Expose the entire ADK agent as a single "skill". The `id` could be the agent's name. `inputModes` and `outputModes` would describe what the agent generally accepts/produces (e.g., "text", "json").
            *   **Option 2 (Tools-as-Skills - More Complex):** Attempt to map individual ADK tools to A2A skills. This is closer to how MCP tools are listed but requires careful schema mapping from ADK tool parameters to something representable as `inputModes`/`outputModes` or an implicit schema for the skill. This might be too granular for A2A's "skill" concept which seems higher-level.
            *   **Recommendation for V1:** Agent-as-a-Skill. The `skills` array would contain one entry representing the overall capability of the ADK agent.

**C. Handling A2A Methods:**

1.  **`tasks/send` (Request/Response & Streaming):**
    *   **Mapping to `ADK::Agent#run_task`:** This is the core interaction.
    *   `params` (`TaskSendParams`):
        *   `id`: The A2A task ID. This needs to be managed. ADK's `Session` has an ID. We might need to map A2A Task ID to ADK Session ID or store the A2A Task ID within the ADK Session state.
        *   `sessionId` (optional): If provided, attempt to resume an ADK session.
        *   `message` (`Message`):
            *   `role`: Map to ADK's `:user` or `:agent` role.
            *   `parts` (Array of `Part`):
                *   `TextPart`: Extract `text` and use as `user_input`.
                *   `FilePart`: Requires handling file uploads/references. ADK currently doesn't have a standard way for tools or agents to receive files directly via `run_task`. This would be a significant addition.
                    *   **V1 Idea:** If `FilePart` contains a `uri`, the agent/tool could be prompted to fetch it. If `bytes`, they'd need to be saved temporarily and the path/reference passed to the agent.
                *   `DataPart`: Map `data` (JSON object) to a structured `user_input` hash for the ADK agent.
        *   `pushNotification` (`PushNotificationConfig`): If the ADK agent supports sending notifications back, this config needs to be stored (e.g., associated with the A2A Task ID / ADK Session).
    *   **ADK Session Management:**
        *   If `TaskSendParams.sessionId` is given, try to load an existing ADK session.
        *   If not, or not found, create a new ADK session. The A2A Task ID might become the ADK Session ID, or be stored within it.
    *   **Execution:** Call `ADK::Agent#run_task`.
    *   **Response (`SendTaskResponse` or `SendTaskStreamingResponse`):**
        *   **Synchronous:** The `result` would be a `Task` object. The `Task.status.message` would contain the agent's final response (mapping ADK's `Event.content`). `Task.artifacts` would need mapping if ADK tools produce file-like outputs.
        *   **Streaming (SSE):** If `tasks/sendSubscribe` was called or agent card indicates streaming:
            *   Return an initial `Task` object with `status.state = "working"`.
            *   Then, as `ADK::Agent` generates events (tool calls, intermediate results, final result), these need to be:
                1.  Published (e.g., via Redis Pub/Sub as discussed for "watch").
                2.  An SSE handler for this A2A connection would subscribe to these events.
                3.  Transform ADK Events into A2A `TaskStatusUpdateEvent` or `TaskArtifactUpdateEvent` and stream them to the client.
                4.  The final agent response becomes a `TaskStatusUpdateEvent` with `final: true` and `status.state = "completed"` or `"failed"`.

2.  **`tasks/get`:**
    *   `params` (`TaskQueryParams`): Contains `id` (A2A Task ID).
    *   Retrieve the ADK Session associated with this A2A Task ID.
    *   Construct and return a `Task` object reflecting the current state of the ADK session (last message, overall status).
    *   `historyLength`: Limit the `Task.history` array.

3.  **`tasks/cancel`:**
    *   `params` (`TaskIdParams`): Contains `id`.
    *   This is tricky for ADK's current model. `ADK::Agent#run_task` is largely synchronous within its turn.
    *   If the task involves a long-running *ADK tool* (e.g., one using Sidekiq or Temporal), then cancellation might involve signaling that background job.
    *   **V1 Approach:** If the task is actively being processed by `run_task`, cancellation might not be possible mid-turn. If it has enqueued an async job, this method could attempt to cancel that Sidekiq/Temporal job.
    *   Return a `Task` object with `status.state = "canceled"`.

4.  **`tasks/pushNotification/set` and `tasks/pushNotification/get`:**
    *   Requires storing the `PushNotificationConfig` (URL, token, auth) associated with an A2A Task ID/ADK Session.
    *   When an ADK agent needs to send a push notification (this would be a new capability for ADK agents/tools), it would retrieve this config and make an HTTP POST request to the `PushNotificationConfig.url`.

**D. Data Part & Artifact Handling**

*   **`TextPart` -> ADK `user_input` (String):** Straightforward.
*   **`DataPart` -> ADK `user_input` (Hash):** The agent's planner/tools would need to be designed to handle structured hash inputs.
*   **`FilePart` -> ADK:** This is the most complex.
    *   If `uri`, the agent could be prompted or a tool could fetch it.
    *   If `bytes` (base64): The A2A handler would need to decode, save to a temporary file, and then pass the file path or a reference to the ADK agent/tool. This implies ADK tools need a way to be told "here's a file path for your input."
*   **ADK Tool Result -> `Artifact`:** If an ADK tool produces a file, the A2A layer would need to read it, potentially base64 encode it (if not using URI), and package it as an `Artifact` with `FilePart`.

**III. Implementing A2A Consumer (Client-Side)**

This allows an ADK agent to call *other* A2A agents.

**A. New `A2ATool < ADK::Tool`**

*   **Purpose:** A generic ADK tool that can call any skill on a remote A2A agent.
*   **Parameters (defined in `tool_description` or `parameter` DSL):**
    *   `target_agent_url` (String, required): Base URL of the target A2A agent.
    *   `skill_id` (String, required): The ID of the skill to invoke on the target agent.
    *   `input_text` (String, optional): Text input for the skill.
    *   `input_data` (Hash, optional): Structured JSON data input.
    *   `input_file_path` (String, optional): Path to a local file to send (A2ATool would read and encode/upload).
    *   *(Authentication parameters might be needed if not handled globally)*
*   **`perform_execution` logic:**
    1.  **Discover Agent Card (Caching Recommended):**
        *   Make a `GET` request to `target_agent_url/agent-card`.
        *   Parse the `AgentCard`. Store/cache it.
        *   Verify the requested `skill_id` exists and check its `inputModes`.
    2.  **Authentication:** Handle authentication based on the `AgentCard.authentication` schemes (e.g., fetch/use API key, OAuth token flow if ADK has a global auth manager). This is a big piece.
    3.  **Construct `Message` `Part`s:** Based on `input_text`, `input_data`, `input_file_path`, create the array of `Part` objects.
    4.  **Call `tasks/send`:**
        *   Use `ADK::Tools::Base::HttpClient` (or a new A2A-specific HTTP client) to make the JSON-RPC call to `target_agent_url/tasks/send`.
        *   Generate a unique A2A Task ID.
    5.  **Handle Response:**
        *   **Synchronous:** Parse the `Task` object from the response. Extract the relevant output from `Task.status.message.parts` or `Task.artifacts`.
        *   **Streaming:** If the target supports streaming and was requested, the `A2ATool` would need to handle the SSE stream. This is complex for a synchronous ADK tool.
            *   **V1 Idea:** For synchronous ADK tools, `A2ATool` might only support the request/response flow of `tasks/send`. If the remote task is long, it would poll `tasks/get` internally until completion or timeout, then return the final result.
            *   **V2 Idea:** A `BaseAsyncA2ATool` could return `:pending` with the A2A Task ID, and a separate `CheckA2ATaskStatusTool` could poll `tasks/get`.
        *   Return result in ADK format: `{status: :success, result: ...}`.

**IV. General ADK Core Changes & Additions**

1.  **Authentication Manager (Significant New Feature):**
    *   A system to manage credentials (API keys, OAuth tokens) that A2A clients (and other HTTP tools) can use.
    *   Secure storage for tokens (potentially leveraging session state with encryption).
    *   Mechanisms for initiating OAuth flows if `A2ATool` needs it (this could get complex, involving callbacks or user interaction prompts).
    *   The `AgentAuthentication` and `AuthenticationInfo` parts of the A2A spec would drive this.

2.  **File Handling in `ADK::Event` and Tools:**
    *   If agents are to receive/send files, `ADK::Event.content` and tool parameter/result structures need a way to represent file paths or temporary file references.

3.  **Configuration (`ADK.configure`):**
    *   Settings for hosting its own A2A service (port, base path, default provider info).
    *   Global authentication settings (e.g., default API keys for certain services).

4.  **Observability Hooks:**
    *   Log A2A requests and responses.
    *   Integrate with existing ADK metrics.

**V. Phased Implementation Approach Recommendation:**

1.  **Phase 1: Basic A2A Provider (Server-Side, Request/Response Only)**
    *   Focus on `AgentCard` generation (agent-as-a-skill).
    *   Implement the A2A HTTP handler for `tasks/send` (synchronous) and `tasks/get`.
    *   Map incoming `TextPart` to `agent.run_task` `user_input`.
    *   Map ADK agent's final string result back to `TextPart` in the A2A `Task` response.
    *   Basic error mapping.
    *   Manual/simple API key authentication for the A2A endpoint.

2.  **Phase 2: Basic A2A Consumer (Client-Side, Request/Response Only)**
    *   Develop the `A2ATool`.
    *   Implement `AgentCard` fetching and parsing.
    *   Implement `tasks/send` for `TextPart` input.
    *   Handle synchronous `Task` response with `TextPart` output.
    *   Basic API key authentication support in `A2ATool`.

3.  **Phase 3: Advanced Data Types (Provider & Consumer)**
    *   Add support for `DataPart` (JSON objects) in both directions.
    *   Start tackling `FilePart` (e.g., URI-based first, then base64 bytes with temporary file storage).

4.  **Phase 4: Streaming & Async (Provider & Consumer)**
    *   **Provider:** Implement SSE for `tasks/sendSubscribe`. Integrate with event publishing (e.g., Redis Pub/Sub from "watch" feature).
    *   **Consumer:** Enhance `A2ATool` (or create `AsyncA2ATool`) to handle SSE responses or to manage polling `tasks/get` for long-running remote tasks.
    *   Implement `tasks/cancel` on the provider side (best effort).

5.  **Phase 5: Push Notifications & Robust Authentication**
    *   Implement `tasks/pushNotification/set` and `/get` on the provider.
    *   Develop a mechanism for ADK agents/tools to trigger these outbound push notifications.
    *   Build out a more comprehensive authentication manager in ADK for both client and server sides (OAuth, etc.).

This is a substantial project. Starting with the core request/response flow for text-based interactions will provide a solid foundation. The A2A spec is rich, so iterative implementation focusing on the most impactful features first would be wise.