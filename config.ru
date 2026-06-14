# File: config.ru

# Load the Legate environment
require_relative 'lib/legate'

# Load specific web components needed for mounting
require_relative 'lib/legate/web/app'
require_relative 'lib/legate/web/webhook_listener'

# Map GEMINI_API_KEY to GOOGLE_API_KEY if only the former is set
# (the gemini-ai gem reads GOOGLE_API_KEY)
ENV['GOOGLE_API_KEY'] ||= ENV['GEMINI_API_KEY'] if ENV['GEMINI_API_KEY']

# Access final Legate configuration
config = Legate.config
webhook_config = config.webhooks

# Build the Rack application stack
app = Rack::Builder.new do
  # Basic Auth for production deployments (enabled when BASIC_AUTH_USER is set)
  if ENV['BASIC_AUTH_USER'] && ENV['BASIC_AUTH_PASSWORD']
    use Rack::Auth::Basic, 'Legate' do |username, password|
      Rack::Utils.secure_compare(username, ENV['BASIC_AUTH_USER']) &
        Rack::Utils.secure_compare(password, ENV['BASIC_AUTH_PASSWORD'])
    end
  end

  # Mount Webhook Listener conditionally
  if webhook_config.listener_enabled
    listener_path = webhook_config.base_path
    Legate.logger.info("[config.ru] Mounting WebhookListener at #{listener_path}")
    map listener_path do
      run Legate::Web::WebhookListener
    end
  else
    Legate.logger.info('[config.ru] WebhookListener disabled, not mounting.')
  end

  # Mount the main Legate Web App at the root
  Legate.logger.info('[config.ru] Mounting main Legate::Web::App at /')
  map '/' do
    run Legate::Web::App
  end
end

# Run the final Rack app
run app
