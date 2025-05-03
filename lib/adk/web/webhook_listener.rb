# File: lib/adk/web/webhook_listener.rb
# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'adk' # To access ADK.config and ADK.logger

module ADK
  module Web
    # Minimal Rack application (using Sinatra) to listen for incoming webhooks.
    # Intended to be mounted within the main ADK::Web::App or run standalone.
    class WebhookListener < Sinatra::Base
      helpers Sinatra::CustomLogger # Use ADK.logger

      configure do
        set :logger, ADK.logger
        # Disable Sinatra's built-in error handling to provide custom responses
        set :show_exceptions, false
        set :raise_errors, false # Let our error handler catch them
        # Prevent Sinatra from starting its own server if run directly (we mount it)
        set :server, :noop
      end

      # --- Middleware/Hooks ---

      before do
        # Ensure request body is parsed as JSON if content type indicates it
        if request.content_type&.match?(/application\/json/i)
          request.body.rewind
          begin
            # Store parsed body in rack env for handlers to access
            env['rack.input.json'] = JSON.parse(request.body.read)
          rescue JSON::ParserError => e
            logger.warn("WebhookListener: Invalid JSON received: #{e.message}")
            halt 400, json({ status: :error, error_message: "Invalid JSON format: #{e.message}" })
          ensure
            request.body.rewind # Ensure body is readable again for potential validation
          end
        end
      end

      # --- Error Handling ---

      error 400..599 do # Catch common client/server errors
        content_type :json
        # Use response body if already set (e.g., by halt), otherwise generic message
        response_body = response.body.first
        if response_body && !response_body.empty?
          response_body
        else
          status_message = Rack::Utils::HTTP_STATUS_CODES[response.status] || 'Error'
          json({ status: :error, error_message: "Webhook Error: #{status_message} (Status #{response.status})" })
        end
      end

      error StandardError do # Catch unexpected internal errors
        e = env['sinatra.error']
        logger.error("WebhookListener Internal Error: #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        content_type :json
        status 500
        json({ status: :error, error_message: "Internal Server Error: #{e.message}" })
      end

      # --- Routing --- 
      # Placeholder for dynamic agent route
      # TODO: Implement dynamic route handler based on config.webhooks.dynamic_agent_route_pattern
      post '/agents/:agent_name/trigger' do # Default pattern
        agent_name = params['agent_name']
        logger.info("WebhookListener: Received dynamic agent trigger for: #{agent_name}")
        # TODO:
        # 1. Check if dynamic handler enabled in config
        # 2. Load agent definition from DefinitionStore
        # 3. Check definition.webhook_enabled
        # 4. Perform validation (using definition.webhook_validator)
        # 5. Perform transformation (using definition.webhook_transformer)
        # 6. Extract session ID (using definition.webhook_session_extractor)
        # 7. Enqueue job to Sidekiq (ADK::WebhookJobWorker)
        # 8. Return 202 Accepted
        content_type :json
        status 202 # Accepted
        json({ status: :accepted, message: "Request for agent '#{agent_name}' queued." })
      end

      # Placeholder for static routes
      # TODO: Add logic to map routes defined in config.webhooks.static_routes
      get '/ping' do # Example static route
        logger.info("WebhookListener: Received static ping")
        content_type :json
        json({ status: :ok, message: "Pong from ADK Webhook Listener" })
      end

      # Catch-all for undefined routes within the listener's base path
      not_found do
        content_type :json
        json({ status: :error, error_message: "Webhook route not found: #{request.request_method} #{request.path_info}" })
      end
    end
  end
end 