# Configuring an Agent for Inbound Webhooks

This guide details how to configure a specific ADK Agent Definition to be triggered by external systems using the ADK's inbound webhook feature.

**Prerequisite:** Ensure the ADK Webhook Listener and the Dynamic Agent Handler are enabled in your global ADK configuration. See the main [`webhooks`](./webhooks) documentation for details on setting up `ADK.configure`:

```ruby
# config/initializers/adk.rb (or similar)
ADK.configure do |config|
  config.webhooks.listener_enabled = true
  config.webhooks.enable_dynamic_agent_handler = true
  # ... other listener settings (port, base_path) ...
end
```

With the dynamic handler enabled (defaulting to the route `/agents/:agent_name/trigger` under the configured `base_path`), you can configure individual agents to respond to requests matching this pattern.

## Agent Definition Webhook Metadata

To make an agent triggerable via the dynamic route, you must define specific metadata within its definition block (`ADK::Agent.define do |a| ... end`).

### 1. Enable Webhook Triggering (`webhook_enabled`)

This is the master switch for exposing the agent via the dynamic webhook route.

*   **Required:** Yes, if you want the agent triggerable by webhook.
*   **Type:** Boolean
*   **Default:** `false`

```ruby
ADK::Agent.define do |a|
  a.name :my_webhook_enabled_agent
  # ... other config ...

  a.webhook_enabled true # MUST be true
end
```

If `webhook_enabled` is not explicitly set to `true`, requests targeting this agent via the dynamic route will result in a `404 Not Found` response.

### 2. Define Payload Transformation (`webhook_transformer`)

This Proc defines how the incoming webhook request payload is converted into the `user_input` expected by your agent's `run_task` method.

*   **Required:** Yes, if `webhook_enabled` is `true`.
*   **Type:** `Proc` (or Lambda)
*   **Signature:** `lambda { |request_body| }`
    *   `request_body`: The parsed request body (typically a Hash if the request Content-Type was `application/json`, otherwise the raw String body).
*   **Return Value:** The `String` or `Hash` that will be passed as the `user_input` parameter to `agent.run_task` by the background worker.
*   **Error Handling:** If the payload is invalid or missing expected data, the Proc should raise an `ADK::WebhookConfigurationError` with a descriptive message. This will cause the listener to return a `400 Bad Request`.

```ruby
ADK::Agent.define do |a|
  # ... name, webhook_enabled true ...

  a.webhook_transformer ->(request_body) do
    # Example: Expecting JSON: { "event_type": "...", "data": { ... } }
    event_type = request_body['event_type']
    event_data = request_body['data']

    unless event_type && event_data
      raise ADK::WebhookConfigurationError, "Payload missing 'event_type' or 'data'."
    end

    # Construct the input for the agent task
    "Process event '#{event_type}' with data: #{event_data.to_json}"
  end
end
```

### 3. Define Session ID Extraction (`webhook_session_extractor`)

This Proc determines the `session_id` to use for the agent task triggered by the webhook. This allows grouping related events into the same agent conversation history.

*   **Required:** Yes, if `webhook_enabled` is `true`.
*   **Type:** `Proc` (or Lambda)
*   **Signature:** `lambda { |request_body| }`
    *   `request_body`: The parsed request body (Hash or String).
*   **Return Value:** A non-empty `String` representing the `session_id`.
*   **Error Handling:** If a suitable ID cannot be extracted, raise `ADK::WebhookConfigurationError`. This results in a `400 Bad Request`.

```ruby
ADK::Agent.define do |a|
  # ... name, webhook_enabled true, transformer ...

  a.webhook_session_extractor ->(request_body) do
    # Example: Use a resource ID from the payload
    resource_id = request_body.dig('resource', 'id')
    unless resource_id.is_a?(String) && !resource_id.empty?
      raise ADK::WebhookConfigurationError, "Missing or invalid 'resource.id' in payload."
    end
    "resource_session_#{resource_id}" # e.g., "resource_session_proj-abc-123"
  end
end
```

### 4. Configure Validation (`webhook_validator`)

Specify how incoming requests should be validated for authenticity. This is highly recommended.

*   **Required:** No (but strongly recommended).
*   **Type:** `Symbol` (referencing a globally registered validator) or `Proc` (for custom logic).
*   **Default:** `nil` (no validation applied unless a global validator is configured).

**Option A: Using a Named Global Validator**

First, register a validator globally (see `webhooks.md`):

```ruby
# config/initializers/adk.rb
ADK.configure do |config|
  # ...
  config.webhooks.register_validator(:hmac_sha256) do |request, secret|
    # ... HMAC validation logic using request and secret ...
  end
end
```

Then, reference it in the agent definition:

```ruby
ADK::Agent.define do |a|
  # ... name, webhook_enabled true, transformer, extractor ...

  a.webhook_validator :hmac_sha256 # Use the named validator
  a.webhook_secret ENV['MY_AGENT_WEBHOOK_SECRET'] # Provide the secret for this agent
end
```

**Option B: Providing a Custom Proc**

Define the validation logic directly within the agent definition.

```ruby
ADK::Agent.define do |a|
  # ... name, webhook_enabled true, transformer, extractor ...

  a.webhook_validator ->(request, secret) do
    # Example: Check for a specific token in headers or params
    # 'secret' here is the value from a.webhook_secret below
    request.params['auth_token'] == secret || request.env['HTTP_X_AUTH_TOKEN'] == secret
  end
  a.webhook_secret ENV['MY_AGENT_AUTH_TOKEN']
end
```

*   **Validator Proc Signature:** `lambda { |request, secret| }`
    *   `request`: The full Rack request object.
    *   `secret`: The value defined by `a.webhook_secret` (or `nil`).
*   **Return Value:** `true` if valid, `false` otherwise.
*   **Error Handling:** If validation fails (returns `false`), the listener returns a `401 Unauthorized` response. If the validator Proc itself raises an error, a `500 Internal Server Error` is returned.

### 5. Provide Validation Secret (`webhook_secret`)

Provides the secret key or token needed by the configured `webhook_validator`.

*   **Required:** Only if the chosen validator logic requires a secret.
*   **Type:** `String`
*   **Default:** `nil`

```ruby
ADK::Agent.define do |a|
  # ... name, webhook_enabled true, transformer, extractor, validator ...

  # Use environment variables for secrets!
  a.webhook_secret ENV['MY_AGENT_WEBHOOK_SECRET']
end
```

## Example: Fully Configured Agent

```ruby
# app/agents/github_issue_agent.rb
require 'adk'
require 'json'
require 'openssl' # Needed if validator uses it

ADK::Agent.define do |a|
  a.name :github_issue_agent
  a.description "Processes updates for GitHub issues via webhooks."
  a.instruction "Analyze the GitHub issue event and associated data."
  # ... add tools, model ...

  # -- Webhook Settings --
  a.webhook_enabled true
  a.webhook_validator :hmac_sha256 # Assumes :hmac_sha256 is registered globally
  a.webhook_secret ENV['GITHUB_ISSUE_WEBHOOK_SECRET']

  a.webhook_session_extractor ->(payload) do
    issue_id = payload.dig('issue', 'id')
    repo_id = payload.dig('repository', 'id')
    unless issue_id && repo_id
      raise ADK::WebhookConfigurationError, "Missing issue or repository ID in payload."
    end
    "github_issue_#{repo_id}_#{issue_id}"
  end

  a.webhook_transformer ->(payload) do
    action = payload['action']
    issue_title = payload.dig('issue', 'title')
    issue_body = payload.dig('issue', 'body')
    sender = payload.dig('sender', 'login')

    unless action && issue_title && sender
      raise ADK::WebhookConfigurationError, "Missing required fields (action, issue.title, sender.login)."
    end

    # Return a hash as input for the agent task
    {
      event_type: "github_issue_#{action}",
      title: issue_title,
      body: issue_body,
      triggered_by: sender
    }
  end
end
```

By defining this metadata, your agent can securely and reliably be triggered by external webhook events, leveraging the ADK's asynchronous processing capabilities. 