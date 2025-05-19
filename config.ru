# File: config.ru

# Load the ADK environment
require_relative 'lib/adk'

# Load specific agent definitions needed by the web process
require_relative 'examples/webhook_receiver_agent'

# Load specific web components needed for mounting
require_relative 'lib/adk/web/app'
require_relative 'lib/adk/web/webhook_listener'

# Access final ADK configuration (assuming ADK.configure has been run by the calling process, e.g., the E2E runner)
config = ADK.config
webhook_config = config.webhooks

# Build the Rack application stack
app = Rack::Builder.new do
  # Mount Webhook Listener conditionally
  if webhook_config.listener_enabled
    listener_path = webhook_config.base_path
    ADK.logger.info("[config.ru] Mounting WebhookListener at #{listener_path}")
    map listener_path do
      run ADK::Web::WebhookListener
    end
  else
    ADK.logger.info("[config.ru] WebhookListener disabled, not mounting.")
  end

  # Mount the main ADK Web App at the root
  ADK.logger.info("[config.ru] Mounting main ADK::Web::App at /")
  map '/' do
    run ADK::Web::App
  end
end

# Run the final Rack app
run app 