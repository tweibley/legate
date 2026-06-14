# File: examples/advanced/webhooks/webhook_e2e_runner.rb
# frozen_string_literal: true

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))

require 'legate'
require_relative 'webhook_receiver_agent' # Ensure agent definition is loaded
require 'openssl'
require 'json'

# --- Configuration ---

# Ensure the secret is set (same as used in webhook_receiver_agent.rb)
# Set this environment variable before running the script:
# export WEBHOOK_RECEIVER_SECRET='a-very-secret-key'
webhook_secret = ENV['WEBHOOK_RECEIVER_SECRET']
unless webhook_secret
  puts 'Error: WEBHOOK_RECEIVER_SECRET environment variable must be set.'
  exit(1)
end

# Configure Legate for the E2E test
Legate.configure do |config|
  # 1. Webhook Listener Settings
  config.webhooks.listener_enabled = true
  config.webhooks.listen_address = 'localhost' # Bind to localhost for this test
  config.webhooks.listen_port = 9293 # Use a non-default port
  config.webhooks.base_path = '/webhooks' # Default base path

  # 2. Enable Dynamic Agent Handler
  config.webhooks.enable_dynamic_agent_handler = true
  # Keep default route pattern: /agents/:agent_name/trigger

  # 3. Session service uses in-memory storage
  config.session_service = Legate::SessionService::InMemory.new
end

# --- Verify Agent Definition Was Loaded and Registered Globally ---
# The `require_relative 'webhook_receiver_agent'` should have defined and globally registered the definition.
begin
  retrieved_def_obj = Legate::GlobalDefinitionRegistry.find(:webhook_receiver)
  raise 'Failed to retrieve :webhook_receiver definition object from Legate::GlobalDefinitionRegistry after loading.' unless retrieved_def_obj && retrieved_def_obj.is_a?(Legate::AgentDefinition) && retrieved_def_obj.name == :webhook_receiver

  puts 'Verified :webhook_receiver definition object exists in GlobalDefinitionRegistry.'
rescue StandardError => e
  puts "Error verifying agent definition in GlobalDefinitionRegistry: #{e.message}"
  exit(1)
end

# --- Process Management ---
web_server_pid = nil

begin
  puts "Starting Legate Web Server (with Webhook Listener) on port #{Legate.config.webhooks.listen_port}..."
  puts '--- Legate Web Server Output START ---'
  # Use rackup with the new config.ru
  port = Legate.config.webhooks.listen_port
  web_server_pid = Process.spawn("bundle exec rackup config.ru -p #{port}")
  # Wait briefly for server to start
  sleep 2

  puts "\nProcess started: Web=#{web_server_pid}"
  puts "Sending webhook trigger using webhook-example.rb...\n---"

  # Execute the sender script
  # Pass listener port/path via ENV vars so sender script knows where to send
  sender_env = {
    'LEGATE_WEBHOOK_PORT' => Legate.config.webhooks.listen_port.to_s,
    'LEGATE_WEBHOOK_BASE_PATH' => Legate.config.webhooks.base_path,
    'WEBHOOK_RECEIVER_SECRET' => webhook_secret # Ensure sender uses the same secret
  }
  sender_success = system(sender_env, 'bundle exec ruby examples/webhook-example.rb')
  puts '---'

  unless sender_success
    puts "\nWebhook sender script failed! Check output above."
    # Don't exit immediately, try to clean up processes
  end

  puts "\nWaiting 5 seconds for job processing..."
  sleep 5

  # --- Verification (Basic Log Check) ---
  puts "\nVerification:"
  puts 'Please check the console output where the web server is running.'
  puts 'You should see log messages indicating the webhook was received and processed.'
rescue Interrupt
  puts "\nInterrupted. Cleaning up..."
rescue StandardError => e
  puts "\nAn error occurred in the runner: #{e.message}"
  puts e.backtrace.join("\n")
ensure
  # --- Cleanup Background Processes ---
  puts "\nCleaning up background processes..."
  if web_server_pid
    puts "Stopping Web server (PID: #{web_server_pid})..."
    begin
      Process.kill('TERM', web_server_pid)
    rescue StandardError
      nil
    end
    begin
      Process.wait(web_server_pid)
    rescue StandardError
      nil
    end # Wait briefly
  end
  puts 'Cleanup complete.'
end
