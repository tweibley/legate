#!/usr/bin/env ruby
# frozen_string_literal: true

# Add the lib directory to the load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'adk'
require 'adk/tools/webhook_tool'
require 'openssl' # For HMAC calculation
require 'json'    # For payload generation

# --- Example Script to Trigger the Webhook Receiver Agent ---

# Configuration
# Use environment variables for sensitive info like secrets and potentially the target URL
# NOTE: The listener URL depends on the configuration in the *runner* script
# (webhook_e2e_runner.rb) - Ensure the port and base_path match!
listener_port = ENV.fetch('ADK_WEBHOOK_PORT', 9292) # Default if not set by runner
listener_base_path = ENV.fetch('ADK_WEBHOOK_BASE_PATH', '/webhooks') # Default if not set
target_agent_name = 'webhook_receiver'
webhook_url = "http://localhost:#{listener_port}#{listener_base_path}/agents/#{target_agent_name}/trigger"

secret_key = ENV['WEBHOOK_RECEIVER_SECRET']
unless secret_key
  puts "\nError: Environment variable WEBHOOK_RECEIVER_SECRET must be set."
  exit(1)
end

puts "Targeting webhook URL: #{webhook_url}"

# Payload matching the receiver's transformer expectation
payload_data = {
  message: 'Hello from the E2E Sender!',
  timestamp: Time.now.iso8601,
  source: 'adk-ruby-webhook-example'
}
payload_json = payload_data.to_json

# Calculate HMAC Signature
calculated_signature = OpenSSL::HMAC.hexdigest('sha256', secret_key, payload_json)
signature_header_value = "sha256=#{calculated_signature}"

# Headers including the signature
custom_headers = {
  'Content-Type' => 'application/json',
  'X-Hub-Signature-256' => signature_header_value
}

# Instantiate the outbound WebhookTool
webhook_tool = ADK::Tools::WebhookTool.new

begin
  ADK.logger.info "Attempting to send webhook trigger to: #{webhook_url}"

  # Execute the tool to send the webhook
  result = webhook_tool.execute(
    url: webhook_url,
    payload: payload_json, # Send the raw JSON string
    headers: custom_headers
    # Secret is used for *calculating* the signature, not passed to the tool here
  )

  # Process the result from the WebhookTool execution
  if result[:status] == :success
    response_status = result.dig(:result, :response_status)
    response_body_str = result.dig(:result, :response_body)
    ADK.logger.info "WebhookTool executed successfully. Response Status: #{response_status}"
    puts "
WebhookTool sent request. Listener responded with status: #{response_status}"
    # Try parsing listener response body
    begin
      response_body = JSON.parse(response_body_str)
      puts "Listener Response Body: #{response_body}"
    rescue JSON::ParserError
      puts "Listener Response Body (non-JSON): #{response_body_str}"
    end
    # Check if the listener accepted the request (202)
    exit(0) if response_status == 202
    exit(1) # Exit with error if listener didn't return 202
  else
    # The WebhookTool itself failed (e.g., connection error)
    ADK.logger.error "WebhookTool failed: #{result[:error_message]}"
    puts "\nError sending webhook via WebhookTool: #{result[:error_message]}"
    exit(1)
  end
rescue ADK::ToolArgumentError => e
  ADK.logger.error "Tool configuration error: #{e.message}"
  puts "\nError: Invalid arguments provided to the WebhookTool. #{e.message}"
  exit(1)
rescue ADK::ToolError => e
  ADK.logger.error "Tool execution error: #{e.message}"
  puts "\nError: Failed to send webhook. #{e.message}"
  exit(1)
rescue StandardError => e
  ADK.logger.fatal "An unexpected error occurred: #{e.message}\n#{e.backtrace.join("\n")}"
  puts "\nAn unexpected error occurred: #{e.message}"
  exit(1)
end
