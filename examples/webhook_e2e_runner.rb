# File: examples/webhook_e2e_runner.rb
# frozen_string_literal: true

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'adk'
require 'adk/definition_store/redis_store' # Use Redis store
require 'adk/session_service/redis' # Need redis service for worker
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

# Configure ADK for the E2E test
ADK.configure do |config|
  # 1. Definition Store: Use RedisStore
  config.definition_store = ADK::DefinitionStore::RedisStore.new(redis_client: Redis.new(ADK.redis_options))

  # 2. Webhook Listener Settings
  config.webhooks.listener_enabled = true
  config.webhooks.listen_address = 'localhost' # Bind to localhost for this test
  config.webhooks.listen_port = 9293 # Use a non-default port
  config.webhooks.base_path = '/webhooks' # Default base path

  # 3. Enable Dynamic Agent Handler
  config.webhooks.enable_dynamic_agent_handler = true
  # Keep default route pattern: /agents/:agent_name/trigger

  # 5. Default Session Service for Worker (Needs to match worker expectation)
  # The listener passes ADK.redis_options to the job payload.
  # Ensure the worker uses RedisSessionService with these options.
  config.webhooks.default_session_service = ADK::SessionService::Redis.new(redis_client: Redis.new(ADK.redis_options))
  # NOTE: This specific instance isn't used directly, but aligns config with worker behavior.
end

# --- Verify Agent Definition Was Loaded and Registered Globally ---
# The `require_relative 'webhook_receiver_agent'` should have defined and globally registered the definition.
begin
  retrieved_def_obj = ADK::GlobalDefinitionRegistry.find(:webhook_receiver)
  unless retrieved_def_obj && retrieved_def_obj.is_a?(ADK::AgentDefinition) && retrieved_def_obj.name == :webhook_receiver
    raise 'Failed to retrieve :webhook_receiver definition object from ADK::GlobalDefinitionRegistry after loading.'
  end

  puts 'Verified :webhook_receiver definition object exists in GlobalDefinitionRegistry.'
rescue => e
  puts "Error verifying agent definition in GlobalDefinitionRegistry: #{e.message}"
  exit(1)
end

# --- Process Management ---
web_server_pid = nil
sidekiq_pid = nil

begin
  puts "Starting ADK Web Server (with Webhook Listener) on port #{ADK.config.webhooks.listen_port}..."
  puts '--- ADK Web Server Output START ---'
  # Use rackup with the new config.ru
  port = ADK.config.webhooks.listen_port
  web_server_pid = Process.spawn("bundle exec rackup config.ru -p #{port}")
  # Wait briefly for server to start
  sleep 2

  puts "Starting Sidekiq worker for 'adk_webhooks' queue..."
  # Run in background, redirect output
  # Ensure the worker can load the ADK environment (hence bundle exec)
  sidekiq_pid = Process.spawn('bundle exec sidekiq -q adk_webhooks -r ./lib/adk.rb')
  # Wait briefly for worker to start
  sleep 2

  puts "\nProcesses started: Web=#{web_server_pid}, Sidekiq=#{sidekiq_pid}"
  puts "Sending webhook trigger using webhook-example.rb...\n---"

  # Execute the sender script
  # Pass listener port/path via ENV vars so sender script knows where to send
  sender_env = {
    'ADK_WEBHOOK_PORT' => ADK.config.webhooks.listen_port.to_s,
    'ADK_WEBHOOK_BASE_PATH' => ADK.config.webhooks.base_path,
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
  # A more robust check would involve querying the SessionService (if Redis)
  # or checking specific output files/databases.
  # For this example, we just inform the user to check the Sidekiq logs.
  puts "\nVerification:"
  puts 'Please check the console output where Sidekiq is running (or its log file).'
  puts 'You should see log messages from WebhookJobWorker indicating the job started'
  puts "and finished, potentially including a log from the agent's run_task method"
  puts "(though the example receiver agent doesn't log explicitly from run_task)."
  puts "Look for logs like: 'WebhookJobWorker starting job:' and 'Agent task finished successfully'"
rescue Interrupt
  puts "\nInterrupted. Cleaning up..."
rescue StandardError => e
  puts "\nAn error occurred in the runner: #{e.message}"
  puts e.backtrace.join("\n")
ensure
  # --- Cleanup Background Processes ---
  puts "\nCleaning up background processes..."
  if sidekiq_pid
    puts "Stopping Sidekiq worker (PID: #{sidekiq_pid})..."
    Process.kill('TERM', sidekiq_pid) rescue nil
    Process.wait(sidekiq_pid) rescue nil # Wait briefly
  end
  if web_server_pid
    puts "Stopping Web server (PID: #{web_server_pid})..."
    Process.kill('TERM', web_server_pid) rescue nil
    Process.wait(web_server_pid) rescue nil # Wait briefly
  end
  puts 'Cleanup complete.'
end
