#!/usr/bin/env ruby
# frozen_string_literal: true

# Add the lib directory to the load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'adk'
require 'adk/tools/webhook_tool'

# --- Example Usage of WebhookTool ---

# Ask the user for their unique Webhook.site URL
puts "Please go to https://webhook.site/ to get a unique URL."
print "Enter your Webhook.site URL: "
webhook_url = gets.chomp

# Basic validation (optional, but recommended)
unless webhook_url.start_with?('http://', 'https://') && webhook_url.include?('webhook.site')
  puts "\nError: Invalid URL format. Please enter a valid URL from webhook.site."
  exit(1)
end

puts "\nUsing webhook URL: #{webhook_url}"

# A sample payload (Hash will be automatically converted to JSON)
payload_data = {
  message: 'Hello from ADK WebhookTool!',
  timestamp: Time.now.iso8601,
  source: 'adk-ruby-interactive-example' # Updated source
}

# Optional: If the webhook requires a signature
# secret_key = 'your_secret_key_here' # Replace with the actual secret if needed

# Optional: Custom headers (e.g., if sending a plain string payload)
# custom_headers = { 'Content-Type' => 'text/plain' }

# Instantiate the tool
webhook_tool = ADK::Tools::WebhookTool.new

begin
  ADK.logger.info "Attempting to send webhook to: #{webhook_url}"

  # Execute the tool
  result = webhook_tool.execute(
    url: webhook_url,
    payload: payload_data
    # secret: secret_key,       # Uncomment if using a secret
    # headers: custom_headers   # Uncomment if adding custom headers
  )

  # Process the result
  if result[:status] == :success
    ADK.logger.info 'Webhook sent successfully!'
    ADK.logger.info "Response Status: #{result.dig(:result, :response_status)}"
    ADK.logger.info "Response Body: #{result.dig(:result, :response_body)}"
    puts "
Webhook sent successfully. Check #{webhook_url.sub('/#!/view/', '/')} to see the request."
    puts "Response Status: #{result.dig(:result, :response_status)}"
  else
    ADK.logger.error "Webhook failed: #{result[:error]}"
    puts "
Webhook failed: #{result[:error]}"
  end

rescue ADK::ToolArgumentError => e
  ADK.logger.error "Configuration error: #{e.message}"
  puts "
Error: Invalid arguments provided to the tool. #{e.message}"
rescue ADK::ToolError => e
  ADK.logger.error "Execution error: #{e.message}"
  puts "
Error: Failed to send webhook. #{e.message}"
rescue StandardError => e
  ADK.logger.fatal "An unexpected error occurred: #{e.message}
#{e.backtrace.join("
")}"
  puts "
An unexpected error occurred: #{e.message}"
end 