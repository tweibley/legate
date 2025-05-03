# File: examples/webhook_receiver_agent.rb
# frozen_string_literal: true

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'adk'
require 'json'

# Example Agent designed to be triggered by an inbound webhook
ADK::Agent.define do |a|
  a.name = :webhook_receiver
  a.description = "Receives simple webhook POSTs and logs the message."
  a.instruction = "You will receive a simple text message. Log it clearly."

  # Tools - maybe just use logger, or add echo for explicitness?
  # For simplicity, the worker will just log the result, no tools needed here.

  # --- Webhook Configuration ---
  a.webhook_enabled true

  # 1. Validator: Use HMAC-SHA256 (defined globally in runner script)
  a.webhook_validator :hmac_sha256
  # Secret MUST be set via ENV['WEBHOOK_RECEIVER_SECRET'] in the runner script
  a.webhook_secret ENV['WEBHOOK_RECEIVER_SECRET'] 

  # 2. Transformer: Expects JSON like {"message": "...", "source": "..."}
  #   Returns the extracted message string for run_task input.
  a.webhook_transformer ->(request_body) do
    msg = request_body['message']
    unless msg.is_a?(String) && !msg.empty?
      raise ADK::WebhookConfigurationError, "Missing or invalid 'message' in webhook payload."
    end
    "Received webhook message: '#{msg}'"
  end

  # 3. Session Extractor: Use a static session ID for all triggers to this agent
  #   Alternatively, could extract based on payload, e.g., request_body['source']
  a.webhook_session_extractor ->(request_body) do
    "webhook_receiver_test_session"
  end
end 