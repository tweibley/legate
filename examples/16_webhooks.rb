#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Sending Webhooks with HMAC Signing
#
# This example demonstrates how to use the built-in WebhookTool to send
# an HMAC-signed webhook payload to an external URL.
#
# Setup:
#   1. Go to https://webhook.site and copy your unique URL
#   2. Run: WEBHOOK_URL=https://webhook.site/your-uuid WEBHOOK_SECRET=my-secret \
#           bundle exec ruby examples/16_webhooks.rb
#   3. Check webhook.site to see the received payload and signature header
#
# Run with: bundle exec ruby examples/16_webhooks.rb

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'legate'

# Load .env and map GEMINI_API_KEY -> GOOGLE_API_KEY (as the `legate` CLI does).
# The library never reads .env on its own; an application must opt in.
Legate.load_environment
require 'legate/tools/webhook_tool'
require 'openssl'
require 'json'

puts '--- Webhook Example ---'

# 1. Configuration
webhook_url = ENV['WEBHOOK_URL']
secret_key = ENV.fetch('WEBHOOK_SECRET', 'example-secret-key')

unless webhook_url
  puts "\nUsage: WEBHOOK_URL=https://webhook.site/your-uuid bundle exec ruby examples/16_webhooks.rb"
  puts "\nGet a free URL at https://webhook.site — then check the site to see your payload arrive."
  puts "You can also set WEBHOOK_SECRET (defaults to 'example-secret-key')."
  exit(1)
end

puts "Target URL: #{webhook_url}"

# 2. Build the payload
payload_data = {
  message: 'Hello from Legate!',
  timestamp: Time.now.iso8601,
  source: 'legate-webhook-example'
}
payload_json = payload_data.to_json

# 3. Calculate HMAC signature (SHA-256)
# The receiver can verify the payload integrity using the same secret
calculated_signature = OpenSSL::HMAC.hexdigest('sha256', secret_key, payload_json)
signature_header_value = "sha256=#{calculated_signature}"

puts "Payload: #{payload_json}"
puts "HMAC Signature: #{signature_header_value}"

# 4. Build headers
custom_headers = {
  'Content-Type' => 'application/json',
  'X-Hub-Signature-256' => signature_header_value
}

# 5. Send the webhook using the built-in WebhookTool
webhook_tool = Legate::Tools::WebhookTool.new

begin
  puts "\nSending webhook..."
  result = webhook_tool.execute(
    url: webhook_url,
    payload: payload_json,
    headers: custom_headers
  )

  if result[:status] == :success
    response_status = result.dig(:result, :response_status)
    response_body = result.dig(:result, :response_body)
    puts 'Webhook sent successfully!'
    puts "  Response status: #{response_status}"
    puts "  Response body: #{response_body}"
  else
    puts "Webhook failed: #{result[:error_message]}"
  end
rescue Legate::ToolError => e
  puts "Tool error: #{e.message}"
rescue StandardError => e
  puts "Unexpected error: #{e.message}"
end

puts "\n--- Example Complete ---"
