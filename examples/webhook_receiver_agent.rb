# File: examples/webhook_receiver_agent.rb
# frozen_string_literal: true

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'adk'
require 'json'

# Example Agent designed to be triggered by an inbound webhook
# This script defines the agent and registers it globally.
# Another process (e.g., a web server running ADK::Web::WebhookListener)
# would look up this definition by name to handle incoming webhooks.

ADK.logger.debug 'Defining agent :webhook_receiver...'

webhook_receiver_definition = ADK::AgentDefinition.new.define do |a|
  a.name(:webhook_receiver)
  a.description('Receives simple webhook POSTs and logs the message.')
  a.instruction('You will receive a simple text message. Log it clearly.')

  # Tools - using echo tool for explicitness.
  a.use_tool :echo

  # --- Webhook Configuration ---
  a.webhook_enabled(true)

  # 1. Validator: Use HMAC-SHA256 (validator logic would be globally registered)
  a.webhook_validator(:hmac_sha256)
  # Secret for HMAC should be set in the environment where the webhook listener runs.
  # For this definition, we can reference an ENV var that the listener would also use.
  a.webhook_secret(ENV['WEBHOOK_RECEIVER_SECRET'] || 'default-secret-for-definition-if-not-set-in-env')

  # 2. Transformer: Expects JSON like {"message": "...", "source": "..."}
  #   Returns the extracted message string for run_task input.
  a.webhook_transformer(->(request_body) do
    # Ensure request_body is parsed if it's a JSON string
    parsed_body = request_body.is_a?(String) ? JSON.parse(request_body) : request_body
    msg = parsed_body['message']
    raise ADK::WebhookConfigurationError, "Missing or invalid 'message' in webhook payload." unless msg.is_a?(String) && !msg.empty?

    "Received webhook message: '#{msg}'"
  rescue JSON::ParserError => e
    raise ADK::WebhookConfigurationError, "Invalid JSON in webhook payload: #{e.message}"
  end)

  # 3. Session Extractor: Use a static session ID for all triggers to this agent
  #   Alternatively, could extract based on payload, e.g., request_body['source']
  a.webhook_session_extractor(->(_request_body) do # Mark _request_body as unused
    'webhook_receiver_test_session'
  end)
end

# Register the definition globally so it can be found by name.
ADK::GlobalDefinitionRegistry.register(webhook_receiver_definition)

ADK.logger.debug "Agent definition '#{webhook_receiver_definition.name}' created and registered globally."
ADK.logger.debug 'Note: This script only defines and registers the agent. A separate webhook listener process is needed to use it.'
