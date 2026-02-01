# Inbound Webhooks

Trigger ADK agents via HTTP webhooks using `POST /webhooks/agents/:agent_name/trigger`.

## Configuration

Enable webhooks in your `ADK::AgentDefinition` and register it globally.

```ruby
# Define and register the agent
agent_def = ADK::AgentDefinition.new.define do |a|
  a.name :webhook_agent
  a.instruction "Process the webhook payload."
  a.use_tool :echo

  # 1. Enable Webhooks
  a.webhook_enabled true

  # 2. Transform Payload (Extracts the user input string)
  a.webhook_transformer ->(payload) {
    "New event: #{payload['event']} from #{payload['source']}"
  }

  # 3. Extract Session ID (Groups requests into sessions)
  a.webhook_session_extractor ->(payload) {
    "session_#{payload['user_id']}"
  }

  # 4. Optional: Validation (e.g., HMAC-SHA256)
  a.webhook_secret ENV['WEBHOOK_SECRET']
  a.webhook_validator :hmac_sha256
end

ADK::GlobalDefinitionRegistry.register(agent_def)
```

## Security

The built-in `:hmac_sha256` validator checks the `X-Hub-Signature-256` header against the payload and your secret.
