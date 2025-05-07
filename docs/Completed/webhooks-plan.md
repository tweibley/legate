# ADK Webhook Integration Plan

This document outlines a plan for integrating webhook capabilities into the ADK Ruby library, enhancing its ability to interact with external systems and trigger agent workflows.

## Background

The ADK currently allows defining Agents with specific tools and executing tasks within sessions. Agents can interact with external systems if provided with appropriate tools (e.g., a tool using `ADK::Tools::Base::HttpClient`). However, there's no built-in mechanism for:

1.  **Triggering Agent Tasks via Incoming Webhooks:** Allowing external systems to initiate an ADK agent's task execution by sending an HTTP request to a specific endpoint.
2.  **Simplified Outgoing Webhook Calls from Agents:** Providing a dedicated, easy-to-use tool for agents to send data to external webhook URLs.

## Goals

*   Enable developers to easily configure ADK applications to listen for incoming webhooks and trigger specific agent tasks based on the webhook payload.
*   Provide a standard, user-friendly `WebhookTool` for agents to make outgoing POST requests to external webhook URLs.
*   Ensure robust handling of agent lifecycle states (running, stopped) in relation to webhook interactions.
*   Maintain the developer-friendly nature of the ADK framework.

## Proposed Design

### 1. Incoming Webhooks (Agent Triggering)

This involves adding a server component to the ADK or providing clear integration patterns with existing Ruby web frameworks (like Sinatra or Rack).

**Components:**

*   **Webhook Listener Service:**
    *   A configurable service (potentially a standalone process or integrated into an existing ADK host process) that listens for HTTP requests on defined routes.
    *   Could leverage a lightweight web server library (e.g., Sinatra, Rack).
    *   Needs configuration for port, base path, security (e.g., secret validation).
*   **Webhook Route Mapping:**
    *   A mechanism to map specific incoming webhook routes (e.g., `/webhooks/github/push`) to:
        *   A target Agent Definition Name.
        *   A transformation function/template to convert the webhook payload into the initial `user_input` for the agent's `run_task` method.
        *   Optionally, logic to extract or define a `session_id` (e.g., based on repository ID, user ID from payload, or creating a new one).
*   **Agent Invocation:**
    *   Upon receiving a valid webhook request, the listener service:
        1.  Validates the request (e.g., signature check).
        2.  Transforms the payload.
        3.  Loads the corresponding Agent definition (using `AgentDefinitionStore`).
        4.  Instantiates the Agent.
        5.  Retrieves or creates a Session using the configured `SessionService` (likely `Redis` for persistence).
        6.  Calls `agent.start` (if not already running globally or manage instance lifecycle per-request/job).
        7.  Calls `agent.run_task` with the session ID and transformed input.
        8.  Handles the agent's response (e.g., return immediate `202 Accepted`, log result, potentially send result to another webhook later).

**Lifecycle Handling:**

*   **Agent Not Running:** The design needs to decide how to handle incoming webhooks if the core agent processing infrastructure isn't active.
    *   **Option A (Recommended): Queueing:** The Webhook Listener Service accepts the request, transforms it, and places a job (containing agent name, session ID, input) onto a background job queue (e.g., Sidekiq, Resque). A separate worker process would pick up these jobs, instantiate the agent, and run the task. This decouples the web request from the agent execution and handles cases where the agent worker might be temporarily down or busy. The listener immediately returns `202 Accepted`.
    *   **Option B: Direct Invocation (with error):** The listener attempts to load and run the agent directly. If the necessary components (like a connection to the LLM or other resources agent needs) aren't ready, it returns an HTTP error (e.g., `503 Service Unavailable`). Less resilient.
*   **Agent Already Running:** If using a queuing system (Option A), this is less of a direct concern for the listener. The worker process handles agent instantiation per job. If using direct invocation (Option B) or a long-running agent model, the listener would need to ensure it interacts with the correct running instance or context.

**Configuration:**

```ruby
# Example configuration (conceptual)
ADK.configure do |config|
  config.webhooks.listen_on = "0.0.0.0:9292"
  config.webhooks.secret = ENV['ADK_WEBHOOK_SECRET'] # For signature validation

  config.webhooks.register_route '/webhooks/crm/new_lead' do |route|
    route.target_agent = :lead_processor_agent
    route.session_service = ADK::SessionService::Redis.new # Use Redis sessions
    route.input_transformer = ->(request_body) {
      # Logic to extract relevant data from webhook payload (request_body)
      # and format it as the initial task input string or hash.
      "Process new lead: #{request_body['lead_name']} from #{request_body['source']}"
    }
    # Optional: Session ID logic
    route.session_id_extractor = ->(request_body) { "crm_lead_#{request_body['lead_id']}" }
    # Optional: Signature validation specific to this route
    route.validator = ->(request) { validate_crm_signature(request) }
  end
end
```

### 2. Outgoing Webhooks (Webhook Tool)

This is simpler and involves creating a new standard ADK Tool.

**Components:**

*   **`ADK::Tools::WebhookTool`:**
    *   A new class inheriting from `ADK::Tool`.
    *   Uses the `ADK::Tools::Base::HttpClient` mixin for making HTTP requests.
    *   Defines standard parameters:
        *   `url` (String, required): The target webhook URL.
        *   `payload` (Hash | String, required): The data to send. If a Hash, it should be automatically JSON-encoded.
        *   `secret` (String, optional): A secret for calculating a signature (e.g., HMAC-SHA256).
        *   `headers` (Hash, optional): Custom headers to include.
    *   The `perform_execution` method:
        1.  Constructs the HTTP request using `http_post`.
        2.  Sets `Content-Type` to `application/json` if the payload is a Hash.
        3.  Calculates and adds a signature header if `secret` is provided (e.g., `X-Hub-Signature-256`).
        4.  Makes the POST request.
        5.  Returns a success/failure status, possibly including the response status code from the target webhook.

**Example Tool Definition:**

```ruby
# lib/adk/tools/webhook_tool.rb
require_relative '../tool'
require_relative 'base/http_client'
require 'openssl'
require 'json'

module ADK
  module Tools
    class WebhookTool < ADK::Tool
      include ADK::Tools::Base::HttpClient

      tool_name :send_webhook # or :post_webhook, :notify_webhook
      tool_description 'Sends a POST request with a JSON payload to a specified webhook URL. Can optionally sign the request.'

      parameter :url, type: :string, required: true, description: 'The target webhook URL.'
      parameter :payload, type: [:hash, :string], required: true, description: 'The data payload to send (Hash will be JSON encoded).'
      parameter :secret, type: :string, required: false, description: 'Optional secret key for calculating HMAC-SHA256 signature.'
      parameter :headers, type: :hash, required: false, description: 'Optional custom headers to include.'

      def initialize(context = nil)
        super(context)
        # Setup http_client without a base_url, as URL is dynamic
        # Allow overriding default timeouts via context or config later?
        setup_http_client(base_url: '', headers: {'Content-Type' => 'application/json'})
      end

      private

      def perform_execution(params, _context)
        url = params.fetch(:url)
        payload = params.fetch(:payload)
        secret = params[:secret]
        custom_headers = params[:headers] || {}

        body_string = payload.is_a?(Hash) ? JSON.generate(payload) : payload.to_s
        request_headers = @http_client.headers.merge(custom_headers) # Start with base headers

        if secret
          signature = OpenSSL::HMAC.hexdigest('sha256', secret, body_string)
          request_headers['X-Hub-Signature-256'] = "sha256=#{signature}"
          ADK.logger.debug("WebhookTool: Calculated signature: #{request_headers['X-Hub-Signature-256']}")
        end

        ADK.logger.info("WebhookTool: Sending POST to #{url}")
        begin
          # Use run_request directly as we don't have a base_url in setup
          # We need to parse the URL to ensure path is handled correctly if base_url was empty
          uri = URI.parse(url)
          # Manually trigger the JSON encoding here as make_http_request won't if body is already string
          encoded_body = payload.is_a?(Hash) ? JSON.generate(payload) : payload
          response = @http_client.run_request(:post, uri.request_uri, encoded_body, request_headers)

          # Faraday's :raise_error middleware handles 4xx/5xx
          ADK.logger.info("WebhookTool: Received response status: #{response.status}")
          { status: :success, response_status: response.status, response_body: response.body.to_s } # Avoid parsing response by default
        rescue ADK::ToolError => e # Catches Faraday errors wrapped by HttpClient
           ADK.logger.error("WebhookTool: Error sending webhook to #{url}: #{e.message}")
           # Return error structure consistent with other tools
           { status: :error, error_message: "Failed to send webhook: #{e.message}" }
        rescue StandardError => e # Catch other unexpected errors
           ADK.logger.error("WebhookTool: Unexpected error sending webhook to #{url}: #{e.class} - #{e.message}")
           { status: :error, error_message: "Unexpected error: #{e.message}" }
        end
      end
    end
  end
end
```

**Lifecycle Handling:**

*   If an agent tries to use this tool but the agent isn't running or cannot make network requests, the underlying `HttpClient` error handling (`ADK::ToolError`) will be triggered and propagated back through the agent's execution flow.

## Developer Experience

*   **Incoming:** Provide clear documentation and examples for configuring the Webhook Listener Service and defining routes/transformers. Potentially offer a CLI command to generate a basic webhook listener setup.
*   **Outgoing:** The `WebhookTool` should be included in the core ADK library, making it readily available for agents simply by adding `:send_webhook` (or the chosen name) to their tool list. Documentation should clearly show how to use it in agent prompts/plans.

## Open Questions / Future Considerations

*   **Security:** How to handle API keys or other authentication methods for incoming webhooks beyond simple shared secrets? (e.g., OAuth callback handling?). Needs robust validation.
*   **Scalability:** For high-volume incoming webhooks, the listener and background job processing infrastructure needs to be scalable.
*   **Error Handling & Retries:** Define strategies for retrying failed outgoing webhook calls or failed agent tasks triggered by incoming webhooks.
*   **Response Handling (Incoming):** Should the agent's final result be sent back synchronously to the webhook caller, or is an asynchronous notification pattern preferred? (Async via queue is likely more robust).
*   **Tool Configuration:** How can developers configure default headers, secrets, or timeouts for the `WebhookTool` more globally, rather than per-call? (Perhaps via ADK configuration).
*   **Alternative Triggers:** Besides webhooks, consider other potential event sources for triggering agents (e.g., message queues, scheduled events).

## Implementation Steps

1.  **(Tool)** Implement `ADK::Tools::WebhookTool` using `HttpClient`. Add tests.
2.  **(Core)** Design and implement the configuration API (`ADK.configure { |c| c.webhooks... }`).
3.  **(Listener - POC)** Create a proof-of-concept Webhook Listener using Sinatra/Rack that handles basic routing, transformation, and queuing (e.g., using Sidekiq).
4.  **(Listener - Integration)** Refine the listener, add security features (signature validation), and integrate it more cleanly (e.g., provide a `rake` task or CLI command to run it).
5.  **(Docs)** Write comprehensive documentation for both incoming and outgoing webhook features.
6.  **(Examples)** Create example applications demonstrating both patterns. 