# ADK Plan: Incoming Webhooks to Trigger Agent Tasks

## 1. Introduction & Goals

This document outlines a detailed plan for enabling external systems to trigger ADK Agent tasks via incoming HTTP webhooks. The primary goals are:

*   **Decoupled Triggering:** Allow external events (e.g., Git push, CRM update, IoT alert) to initiate specific agent workflows without direct code integration.
*   **Asynchronous Processing:** Ensure the webhook endpoint responds quickly (`202 Accepted`) and reliably queues the agent task for background execution.
*   **Flexibility & Configuration:** Provide developers with easy ways to define webhook routes, validate requests, transform payloads, and map them to the correct agent and session.
*   **Robustness:** Handle potential errors gracefully at each stage (validation, transformation, queuing, agent execution).
*   **Agent Lifecycle Agnosticism:** Trigger tasks on demand without requiring the target agent definition to correspond to a perpetually running process managed by `agent.start()`.

## 2. High-Level Architecture

The proposed flow involves several key components working together:

```
                                                                       +---------------------------------+
                                                                       | Agent Definition Store          |
                                                                       | (Incl. Webhook Metadata)        |
                                                                       +-------------+-------------------+
                                                                                     ^ Load Definition & Metadata
                                                                                     | (at request time)
External System --(HTTP Request)--> [Webhook Listener]                               |
                                       |                                             |
                                       V                                             |
                                [Router] --(Route Match)--> [Dynamic Agent Handler] --+
                                       |                            |
                                       | (Valid Request)            V Validation, Transformation, Session Extraction
                                       |                            | (Using Metadata)
       (Static Routes - Optional) -----+                            |
                                                                    V (Job Payload: agent_name, session_id, user_input)
                                                           [Background Job Queue (e.g., Sidekiq)]
                                                                    |
                                                                    V (Dequeues Job)
                                                             [Webhook Worker]
                                                                    |
                                                                    V (Loads Definition, Gets Session)
                                                       [Agent Definition] & [Session Service]
                                                                    |
                                                                    V (Instantiates Agent, Calls run_task)
                                                              [Agent Instance] --(Logs Events)--> [Session Service]
                                                                    |
                                                                    V (Task Result)
                                                             [Worker Logging/Notification (Optional)]
```

## 3. Core Components

### 3.1. Webhook Listener

*   **Technology:** A lightweight Rack-based application (e.g., using Sinatra) that can be run as a standalone process or mounted within a larger Rails/Rack application.
*   **Responsibilities:**
    *   Listen for HTTP requests on a configurable port/address and base path.
    *   Parse incoming request data (JSON, form data, headers).
    *   Pass requests to the Router.
    *   Return immediate HTTP responses (e.g., `202 Accepted`, `400 Bad Request`, `401 Unauthorized`, `404 Not Found`).

### 3.2. Webhook Router & Registry

*   **Mechanism:** Primarily configured within the ADK framework (e.g., `ADK.configure` block) to enable the listener and define base paths/globals. Routing can be static or dynamic.
*   **Static Routes (Optional):** Developers *can* still define specific, static routes (e.g., `POST /webhooks/system/status`) using `config.webhooks.register_route` for fixed endpoints.
*   **Dynamic Agent Route Handler (Recommended for Agents):** A configurable route pattern (e.g., `POST /webhooks/agents/:agent_name/trigger`) acts as a generic entry point. When this pattern is matched:
    *   The handler extracts the `agent_name`.
    *   It looks up the corresponding Agent Definition using `ADK::DefinitionStore`.
    *   It retrieves webhook configuration (validation, transformation, etc.) from the **Agent Definition's metadata** (see below).
    *   It processes the request based on that metadata.
*   **Configuration Source:** Listener settings and static routes are in `ADK.configure`. Configuration for dynamic agent routes resides within or alongside the Agent Definition itself.

### 3.3. Request Validator

*   **Purpose:** Ensure the incoming request is legitimate before processing.
*   **Implementation:** Pluggable validation logic. Common strategies:
    *   **HMAC Signature Validation:** Comparing a request header (e.g., `X-Hub-Signature-256`) with a signature calculated using a shared secret and the request body.
    *   **IP Address Filtering:** Allowing requests only from specific IP addresses.
    *   **Basic Authentication:** Checking `Authorization` header.
    *   **Custom Logic:** Allowing developers to provide a Proc/Lambda that receives the `request` object and returns `true` or `false`.
*   **Scope:** Can be defined globally (applied to all webhook routes) and/or per-route.

### 3.4. Payload Transformer

*   **Purpose:** Convert the raw webhook request body (and potentially headers/query params) into the specific `user_input` string or hash expected by the target agent's `run_task` method.
*   **Implementation:** A Proc/Lambda provided during route configuration. It receives the request body (parsed) and potentially the full request object.
*   **Example:** Extracting commit messages and author from a GitHub push payload to form an input like `"Summarize commit by #{author}: #{message}"`.

### 3.5. Session ID Extractor

*   **Purpose:** Determine the appropriate `session_id` for the agent task. This allows related webhook events to be processed within the same agent conversation history.
*   **Implementation:** A Proc/Lambda provided during route configuration. Receives the request body/object.
*   **Strategies:**
    *   Extract from payload (e.g., `repository_id`, `user_id`, `issue_number`).
    *   Generate a unique ID per request (if each webhook represents a distinct task).
    *   Use a static ID for singleton agents processing global events.
*   **Default:** If not provided, a new unique session ID might be generated for each request (configurable behavior).

### 3.6. Background Job Queue

*   **Technology:** Sidekiq is recommended due to its existing integration potential (`CheckJobStatusTool`). Other ActiveJob-compatible backends could also work.
*   **Job Payload:** A simple hash containing:
    *   `agent_definition_name`: The symbol identifying the agent to run.
    *   `session_id`: The string determined by the Session ID Extractor (from agent metadata or static route config).
    *   `transformed_user_input`: The string or hash produced by the Payload Transformer (from agent metadata or static route config).
    *   `session_service_config`: Information needed to instantiate the correct Session Service instance within the worker (e.g., Redis connection details).

### 3.7. Webhook Worker

*   **Technology:** A Sidekiq worker class (e.g., `ADK::WebhookJobWorker`).
*   **Responsibilities:**
    *   Dequeue jobs from the queue.
    *   Parse the job payload.
    *   Retrieve the appropriate `SessionService` instance.
    *   Load the specified `AgentDefinition` (using `ADK::DefinitionStore`). **Crucially, this happens in the worker just before execution.**
    *   Instantiate the `Agent` from the definition.
    *   Retrieve or initialize the `ADK::Session` using the `session_id` and `SessionService`.
    *   Execute the task: `agent.run_task(session_id: ..., user_input: ..., session_service: ...)`.
    *   Log the outcome of `run_task`.
    *   Optionally, perform actions based on the result.

### 3.8. Agent Definition Webhook Metadata (NEW)

*   **Purpose:** To allow Agent Definitions themselves to declare how they can be triggered via the dynamic agent route handler.
*   **Mechanism:** Defined within the agent's definition source (e.g., using methods within the `Agent.define` block or a separate configuration file/database record associated with the definition).
*   **Metadata Fields:**
    *   `webhook_enabled` (Boolean): MUST be set to `true` to allow triggering via the dynamic route. Defaults to `false`. **Security critical.**
    *   `webhook_validator` (Proc/Lambda/Symbol): Logic or reference to a named validator to use for incoming requests for this agent. Can use global validators configured in `ADK.configure`.
    *   `webhook_secret` (String): A specific secret key used by the validator (e.g., for HMAC). Overrides any global secret.
    *   `webhook_transformer` (Proc/Lambda): Required if `webhook_enabled` is true. Converts the raw request payload into the `user_input` for `agent.run_task`.
    *   `webhook_session_extractor` (Proc/Lambda): Required if `webhook_enabled` is true. Determines the `session_id` from the request payload/headers.

## 4. Configuration Example

### 4.1. Central Configuration (`ADK.configure`)

```ruby
# config/initializers/adk.rb or similar
require 'adk'
require 'adk/session_service/redis'
require 'json'
require 'openssl'
require 'active_support/security_utils' # For secure_compare

ADK.configure do |config|
  # --- Listener Configuration ---
  config.webhooks.listener_enabled = true
  config.webhooks.listen_address = "0.0.0.0"
  config.webhooks.listen_port = 9292
  config.webhooks.base_path = "/webhooks" # Recommended base path

  # --- Dynamic Agent Route ---
  # Enable the dynamic handler and optionally customize its path pattern
  config.webhooks.enable_dynamic_agent_handler = true
  # config.webhooks.dynamic_agent_route_pattern = '/invoke/:agent_name' # Optional override

  # --- Global Security (Example: HMAC Validator) ---
  # Define named validators that agent metadata can reference
  config.webhooks.register_validator(:hmac_sha256) do |request, secret|
    return false unless secret
    signature_header = request.env['HTTP_X_HUB_SIGNATURE_256']
    return false unless signature_header&.start_with?('sha256=')
    expected_signature = signature_header.delete_prefix('sha256=')
    request.body.rewind
    payload_body = request.body.read
    request.body.rewind # Leave body readable for transformer
    calculated_signature = OpenSSL::HMAC.hexdigest('sha256', secret, payload_body)
    ActiveSupport::SecurityUtils.secure_compare(calculated_signature, expected_signature)
  end
  # config.webhooks.global_validator = :hmac_sha256 # Optional: Apply globally if no agent validator set
  # config.webhooks.global_secret = ENV['ADK_GLOBAL_WEBHOOK_SECRET'] # Optional global secret

  # --- Default Session Service (used by worker if not specified elsewhere) ---
  config.webhooks.default_session_service = ADK::SessionService::Redis.new(
    redis_url: ENV['REDIS_URL'] || 'redis://localhost:6379/1'
  )

  # --- Static Route Definition (Example - Optional) ---
  # config.webhooks.register_route('GET /system/health') do |route|
  #   route.handler = ->(request) { [200, {'Content-Type' => 'application/json'}, [{status: 'OK'}.to_json]] }
  # end
end
```

### 4.2. Agent Definition with Webhook Metadata (Example)

```ruby
# app/agents/git_commit_summarizer_agent.rb (or loaded via DefinitionStore)
require 'adk'

ADK::Agent.define do |a|
  a.name = :git_commit_summarizer_agent
  a.description = "Summarizes commits from GitHub webhook pushes."
  a.instruction = "You will receive commit details. Summarize them concisely."
  # Define tools needed by the agent, model_name, etc.

  # --- Webhook Configuration Metadata ---
  a.webhook_enabled = true # Expose this agent via POST /webhooks/agents/git_commit_summarizer_agent/trigger
  a.webhook_validator = :hmac_sha256 # Use the named validator defined globally
  a.webhook_secret = ENV['GITHUB_WEBHOOK_SECRET'] # Specific secret for this webhook

  a.webhook_session_extractor = ->(request_body) {
    # Use repository ID as session key
    repo_id = request_body.dig('repository', 'id')
    raise ADK::WebhookConfigurationError, "Missing repository ID in payload" unless repo_id
    "github_repo_#{repo_id}"
  }

  a.webhook_transformer = ->(request_body) {
    # Extract relevant info for the agent task input
    commits = request_body.fetch('commits', [])
    pusher_name = request_body.dig('pusher', 'name') || 'Unknown Pusher'
    if commits.empty?
      return "Received push event from #{pusher_name} with no commits." # Handle edge case
    end
    commit_messages = commits.map { |c| "- #{c['message']} (by #{c.dig('author','name')})" }.join("
")
    "New push by #{pusher_name}. Summarize commits:
#{commit_messages}"
  }
end

# Another agent, NOT exposed via webhook (default)
ADK::Agent.define do |a|
  a.name = :internal_data_processor
  # ... configuration ...
  # a.webhook_enabled is implicitly false
end
```

## 5. Workflow Details

### 5.1. Static Route Workflow (Optional)

1.  Request hits a statically defined route (e.g., `GET /webhooks/system/health`).
2.  Listener matches the route in its static table.
3.  Listener executes the associated handler defined in `ADK.configure`.
4.  Handler returns response directly.

### 5.2. Dynamic Agent Workflow (Primary)

1.  **Request Reception:** Listener receives `POST /webhooks/agents/git_commit_summarizer_agent/trigger` (assuming default pattern and base path).
2.  **Routing:** Listener matches the dynamic agent route pattern. Extracts `agent_name` (`:git_commit_summarizer_agent`).
3.  **Definition Lookup:** Dynamic handler calls `ADK::DefinitionStore.find(:git_commit_summarizer_agent)` to load the agent definition. Returns `404 Not Found` if definition doesn't exist.
4.  **Metadata Check:** Handler checks `webhook_enabled` metadata. Returns `403 Forbidden` or `404 Not Found` if not `true`.
5.  **Validation:** Retrieves `webhook_validator` (`:hmac_sha256`) and `webhook_secret` from metadata. Executes the validator function using the secret. Returns `401 Unauthorized` or `403 Forbidden` on failure.
6.  **Transformation:** Retrieves `webhook_transformer` lambda from metadata. Executes it with the request body, producing the `user_input` string/hash. Returns `400 Bad Request` or `500 Internal Server Error` if transformation fails.
7.  **Session ID Extraction:** Retrieves `webhook_session_extractor` lambda from metadata. Executes it, getting `"github_repo_12345"`. Returns `400 Bad Request` or `500 Internal Server Error` if extraction fails.
8.  **Enqueuing:** Pushes a job to Sidekiq: `{ queue: 'adk_webhooks', class: 'ADK::WebhookJobWorker', args: [{ agent_definition_name: 'git_commit_summarizer_agent', session_id: 'github_repo_12345', transformed_user_input: "New push by...", session_service_config: {...} }] }`. Returns `503 Service Unavailable` if queueing fails.
9.  **Response:** Listener returns `202 Accepted` to the external system (GitHub).
10. **Job Processing (Worker - later):**
    *   Sidekiq worker picks up the job.
    *   Instantiates `SessionService` (e.g., `ADK::SessionService::Redis`) using config.
    *   Loads the `:git_commit_summarizer_agent` definition *again* (workers are separate processes).
    *   Instantiates `Agent`.
    *   Calls `session_service.get_session(session_id: 'github_repo_12345')`.
    *   Calls `agent.run_task(...)`.
    *   Worker logs outcome.

## 6. Agent Lifecycle Handling

*   **On-Demand Instantiation:** Agent *instances* are created by the Sidekiq worker just-in-time to handle a dequeued job.
*   **Dynamic Definition Loading:** The webhook listener's dynamic handler loads the agent *definition* (including webhook metadata) from the `DefinitionStore` *at request time*. This ensures that newly added or updated agent definitions are immediately usable via webhooks, provided they are correctly configured and discoverable by the `DefinitionStore`.
*   **Stateless Listener/Worker:** The listener and worker processes themselves are generally stateless regarding specific agent instances. State lives in the Session Service and the Agent Definitions.
*   **No Listener Restarts Needed:** Adding/updating agent definitions with webhook metadata does **not** require restarting the webhook listener process.

## 7. Security Considerations

*   **HTTPS:** The listener endpoint *must* be served over HTTPS in production.
*   **Secret Management:** Use environment variables or secure secret management systems for webhook secrets. Avoid hardcoding.
*   **Signature Validation:** Strongly recommend HMAC or similar validation for all routes handling sensitive data or triggering significant actions.
*   **Input Sanitization:** While the transformer shapes input, be mindful of potential injection if the agent's tools or prompts improperly handle the transformed input.
*   **Rate Limiting:** Consider adding rate limiting to the listener endpoint to prevent abuse.

## 8. Error Handling & Retries

*   **Listener:** Returns appropriate HTTP error codes (`400`, `401`, `403`, `404`, `500`). Logs errors.
*   **Validation/Transformation:** Errors during these steps should be caught, logged, and result in a `400 Bad Request` or `500 Internal Server Error`.
*   **Enqueuing:** Errors talking to the queue backend (e.g., Redis down) should result in a `503 Service Unavailable` and be logged.
*   **Sidekiq Worker:**
    *   Use Sidekiq's built-in retry mechanisms for transient errors (e.g., temporary network issues during `run_task`).
    *   Catch specific exceptions during agent loading or `run_task` execution (e.g., `ADK::DefinitionNotFound`, `ADK::ToolError`).
    *   Log detailed errors, including agent name, session ID, and input payload, for debugging.
    *   After exhausting retries, move jobs to the Dead Set for manual inspection.

## 9. Deployment Considerations

*   **Development Environment:** For development, the recommended approach is to run the Webhook Listener *within* the main ADK Web UI process started by the existing `adk web start` CLI command. This is achieved by conditionally mounting the Webhook Listener Rack application within the main application's `config.ru` (or equivalent Rack setup).
*   **Production Environment:**
    *   **Option A (Standalone):** Run the Sinatra/Rack listener application as a separate, dedicated process (e.g., via `puma`, `unicorn`) managed by a process supervisor (e.g., `systemd`). This provides better isolation and independent scaling for webhook handling.
    *   **Option B (Mounted):** Continue mounting the listener within the main web application process if resource usage and security posture allow.
*   **Sidekiq Workers:** Run one or more Sidekiq worker processes configured to listen to the `adk_webhooks` queue (or relevant queues).
*   **Dependencies:** Ensure the listener (whether standalone or mounted) and worker environments have access to necessary gems (ADK, Sinatra, Sidekiq, Redis client, etc.) and configurations (environment variables).

## 10. Developer Experience

*   **Simplified Startup (Dev):** Use the existing `adk web start` command (or equivalent). In development mode, this single command will start both the main Web UI and the integrated Webhook Listener (if enabled in config).
*   **Clear Documentation:** Provide documentation for central configuration (`ADK.configure`), defining agent webhook metadata, implementing validators/transformers, deployment options (dev vs. prod), and examples.
*   **Examples:** Include example webhook-enabled agent definitions.
*   **Generator:** Consider a generator command (e.g., `adk generate agent my_agent --webhook-enabled`) to scaffold an agent definition file with placeholder webhook metadata.

## 11. Future Considerations

*   Support for other request content types (XML, form-encoded) besides JSON.
*   More sophisticated validation mechanisms (OAuth callbacks).
*   Option for synchronous responses (wait for `run_task` completion), though async is generally preferred for webhooks.
*   Throttling/Rate-limiting built-in to the listener.
*   Mechanisms for the agent task (running in the worker) to report its final result back to an external system (e.g., using the *outgoing* `WebhookTool`).
*   Caching layer for Agent Definition lookups in the dynamic handler to optimize performance under load.
*   Standardized error reporting formats from validators/transformers.

## 12. Testing Strategy (Specs)

Testing this feature requires a multi-layered approach:

### 12.1. Unit Tests

*   **Configuration (`ADK::Configuration::Webhooks`):**
    *   Test default values (listener disabled, default base path, dynamic handler disabled).
    *   Test setting/getting listener options (enabled, address, port, base path).
    *   Test enabling/disabling dynamic agent handler and setting its pattern.
    *   Test registration and retrieval of named validators.
    *   Test setting default session service.
*   **Validators:**
    *   Test individual validator logic (e.g., HMAC signature calculation/comparison) in isolation with mock requests/secrets.
    *   Test named validator lookup via `ADK.config.webhooks.find_validator`.
*   **Agent Definition Metadata:**
    *   Test accessing webhook metadata (enabled, validator, secret, transformer, extractor) from a loaded `AgentDefinition` instance (requires potentially extending `AgentDefinition` or its loader).
    *   Test default values (`webhook_enabled = false`).
*   **Payload Transformers/Session Extractors:**
    *   Test the logic of individual transformer/extractor lambdas defined in agent metadata with sample request bodies. Test edge cases and error handling (e.g., missing keys).
*   **Dynamic Agent Handler Logic:**
    *   Mock `ADK::DefinitionStore`. Test lookup of agent definitions.
    *   Test enforcement of `webhook_enabled = true`.
    *   Test retrieval and application of validator, transformer, extractor from mocked metadata.
    *   Test correct job payload construction for enqueuing.
    *   Test error handling paths (definition not found, disabled, validation fail, transform fail, extraction fail).
*   **Webhook Worker (`ADK::WebhookJobWorker`):**
    *   Mock `ADK::DefinitionStore`, `SessionService`, and `Agent`.
    *   Test parsing the job payload.
    *   Test loading the correct agent definition.
    *   Test instantiating the correct session service.
    *   Test calling `session_service.get_session`.
    *   Test instantiating the correct agent.
    *   Test calling `agent.run_task` with the correct arguments.
    *   Test basic success/error logging.
*   **Static Route Handling (if implemented):**
    *   Test registration and matching of static routes.
    *   Test execution of simple static route handlers.

### 12.2. Integration Tests

*   **Listener Request Handling (Mocked Queue):**
    *   Use a Rack testing framework (e.g., `rack-test`) to send mock HTTP requests to the listener app.
    *   Mock the background job queue (e.g., Sidekiq::Testing.fake!).
    *   **Scenario 1 (Dynamic Agent):** Send a request to `/webhooks/agents/test_agent/trigger`.
        *   Mock `ADK::DefinitionStore` to return a definition with valid webhook metadata.
        *   Verify the correct job (`ADK::WebhookJobWorker`) is enqueued with the expected arguments (agent name, session id, transformed input).
        *   Verify a `202 Accepted` response.
    *   **Scenario 2 (Validation Fail):** Send a request with an invalid signature. Verify a `401`/`403` response and no job enqueued.
    *   **Scenario 3 (Transform/Extract Fail):** Send a request with a malformed payload. Mock the transformer/extractor to raise an error. Verify a `400`/`500` response and no job enqueued.
    *   **Scenario 4 (Agent Not Found/Disabled):** Send a request for an agent that doesn't exist or has `webhook_enabled = false`. Verify a `404`/`403` response.
    *   **Scenario 5 (Static Route):** Send a request to a defined static route. Verify the expected direct response (e.g., `200 OK`).
*   **End-to-End (Worker Execution - Mocked Agent):**
    *   Use `Sidekiq::Testing.inline!` to execute the worker job immediately upon enqueuing.
    *   Send a valid request to the listener (as above).
    *   Mock `ADK::DefinitionStore` to load the definition.
    *   Mock the `Agent` instance's `run_task` method.
    *   Verify that the `ADK::WebhookJobWorker` executes, loads the definition, gets the session, and calls `agent.run_task` with the correctly transformed input and session ID.
    *   Verify session events are logged (mock `SessionService.append_event`).

## 13. Implementation Checklist

1.  **Configuration:**
    *   [X] Extend `ADK::Configuration` with a `Webhooks` sub-configuration object (`config.webhooks`).
    *   [X] Add config options: `listener_enabled`, `listen_address`, `listen_port`, `base_path`.
    *   [X] Add config options: `enable_dynamic_agent_handler`, `dynamic_agent_route_pattern`.
    *   [X] Add config mechanism for registering/retrieving named validators (`register_validator`, `find_validator`).
    *   [X] Add config for global validator/secret (optional).
    *   [X] Add config for default session service.
    *   [X] Add config mechanism for registering static routes (`register_route`).
    *   [X] Add unit tests for Webhooks configuration.
2.  **Agent Definition Metadata:**
    *   [X] Decide on the mechanism for defining webhook metadata (e.g., methods within `Agent.define` block).
    *   [X] Implement storage/retrieval of metadata fields: `webhook_enabled`, `webhook_validator`, `webhook_secret`, `webhook_transformer`, `webhook_session_extractor`. Ensure `enabled` defaults to `false`.
    *   [X] Update `ADK::Agent` or `ADK::DefinitionStore` accordingly.
    *   [X] Add unit tests for metadata access.
3.  **Webhook Listener (Rack App):**
    *   [X] Create a basic Sinatra/Rack application (`ADK::Web::WebhookListener`).
    *   [X] Implement logic to read ADK configuration for listener settings (port, address, base path).
    *   [X] Implement routing logic:
        *   [X] Mount static routes defined in config.
        *   [X] Mount dynamic agent handler if enabled, using the configured pattern.
    *   [X] Implement request body parsing (JSON primarily). Ensure body is rewindable.
    *   [X] Implement basic error handling middleware.
    *   [X] Modify `config.ru` (or equivalent Rack setup used by `adk web start`): Conditionally mount `ADK::Web::WebhookListener` at `config.webhooks.base_path` based on `config.webhooks.listener_enabled` and development/test environment.
4.  **Dynamic Agent Handler:**
    *   [X] Implement the handler logic triggered by the dynamic route pattern.
    *   [X] Extract `agent_name` from the request path.
    *   [X] Use `ADK::DefinitionStore` to find the agent definition. Handle not found case (404).
    *   [X] Check `webhook_enabled` metadata (403/404 if false).
    *   [X] Retrieve validator config; find named validator via `config.webhooks.find_validator`; execute validation. Handle failure (401/403).
    *   [X] Retrieve and execute `webhook_transformer`. Handle errors (400/500).
    *   [X] Retrieve and execute `webhook_session_extractor`. Handle errors (400/500).
    *   [X] Construct job payload hash.
    *   [X] Enqueue job using Sidekiq client API (`ADK::WebhookJobWorker.perform_async`). Handle enqueue errors (503).
    *   [X] Return `202 Accepted` on success.
    *   [X] Add unit tests for handler logic (mocking DefinitionStore, queue).
5.  **Webhook Worker:**
    *   [X] Create `ADK::WebhookJobWorker` Sidekiq worker class.
    *   [X] Implement `perform` method accepting the job payload hash.
    *   [X] Parse payload: `agent_definition_name`, `session_id`, `transformed_user_input`, `session_service_config`.
    *   [X] Instantiate the correct `SessionService`.
    *   [X] Load the `AgentDefinition` using `ADK::DefinitionStore`. Handle errors.
    *   [X] Instantiate the `Agent`. Handle errors.
    *   [X] Get/Create the `ADK::Session` via the `SessionService`. Handle errors.
    *   [X] Call `agent.run_task` with `session_id`, `transformed_user_input`, and `session_service`.
    *   [X] Log success/failure of the task execution.
    *   [X] Add unit tests for worker logic (mocking dependencies).
6.  **Integration & Plumbing:**
    *   [ ] Ensure Sidekiq is a dependency (potentially optional, guarded).
    *   [X] Verify `adk web start` command correctly boots the combined app (UI + Listener) in development mode.
    *   [X] Add integration tests using `rack-test` (targeting the mounted app) and `Sidekiq::Testing`.
7.  **Documentation:**
    *   [X] Update `README.md` with overview of webhook features.
    *   [X] Write detailed documentation on configuring the listener (`ADK.configure`).
    *   [X] Write detailed documentation on defining Agent webhook metadata.
    *   [X] Provide examples of common validators (HMAC), transformers, and session extractors.
    *   [X] Document deployment considerations (running listener, workers).
8.  **CLI Generator (Optional):**
    *   [X] Implement `adk generate agent <name> --webhook-enabled` command to scaffold agent definition with webhook metadata placeholders.