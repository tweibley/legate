# frozen_string_literal: true

require 'rack' # Required for Rack::Builder and Rack::Server
require 'adk' # Load ADK core for config access
require_relative '../web/app'
# Webhook listener required conditionally below

module ADK
  module CLI
    # CLI commands for web interface
    class WebCommands < Thor
      desc 'start', 'Start the web interface'
      method_option :port, type: :numeric, default: 4567, desc: 'Port to listen on'
      method_option :host, type: :string, default: 'localhost', desc: 'Host to bind to'
      def start
        # Access config early
        webhook_config = ADK.config.webhooks
        listener_enabled = webhook_config.listener_enabled
        listener_base_path = webhook_config.base_path

        # Build the Rack application stack
        app = Rack::Builder.new do
          # Conditionally mount the Webhook Listener
          if listener_enabled
            ADK.logger.info "Webhook listener enabled, mounting at #{listener_base_path}"
            begin
              require_relative '../web/webhook_listener'
              map listener_base_path do
                run ADK::Web::WebhookListener.new
              end
            rescue LoadError => e
              ADK.logger.error "Failed to load WebhookListener: #{e.message}. Listener will not be mounted."
            rescue StandardError => e
              ADK.logger.error "Error initializing WebhookListener: #{e.message}. Listener will not be mounted."
            end
          else
            ADK.logger.debug "Webhook listener is disabled."
          end

          # Mount the main ADK Web App at the root
          run ADK::Web::App.new
        end.to_app # Convert builder block to a Rack app

        # Start the server using Rack::Server
        puts "Starting ADK web interface on http://#{options[:host]}:#{options[:port]}"
        Rack::Server.start(
          app: app,
          Host: options[:host],
          Port: options[:port],
          server: 'puma' # Or thin, webrick etc. Puma is common.
        )
      end
    end
  end
end
