# File: lib/adk/web/webhook_listener.rb
# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'sidekiq' # For Sidekiq::Client.push
require 'adk' # To access ADK.config, ADK.logger, ADK.definition_store
require 'adk/errors' # For ADK::WebhookConfigurationError

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

      error ADK::WebhookConfigurationError do # Specific handling for config errors
        e = env['sinatra.error']
        logger.warn("Webhook Configuration Error: #{e.message}")
        content_type :json
        status 400 # Bad Request, likely due to payload issues during extraction/transform
        json({ status: :error, error_message: "Configuration Error: #{e.message}" })
      end

      error ADK::DefinitionStore::DefinitionNotFound do
        e = env['sinatra.error']
        logger.warn("Agent definition not found: #{e.message}")
        content_type :json
        status 404
        json({ status: :error, error_message: "Agent definition not found." })
      end

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

      # Route for dynamically triggering agent tasks via webhooks.
      post '/agents/:agent_name/trigger' do # Default pattern
        webhook_config = ADK.config.webhooks
        agent_name_sym = params['agent_name']&.to_sym
        raw_request_body = env['rack.input.json'] || request.body.read # Prefer parsed JSON
        request.body.rewind # Ensure body is readable again if needed

        logger.info("WebhookListener: Received dynamic agent trigger for: #{agent_name_sym}")

        # 1. Check if dynamic handler enabled
        unless webhook_config.enable_dynamic_agent_handler
          logger.warn("Dynamic agent handler is disabled, rejecting request for #{agent_name_sym}.")
          halt 403, json({ status: :error, error_message: "Dynamic agent webhooks are disabled." })
        end

        # 2. Load agent definition
        # Errors like DefinitionNotFound are caught by the error handlers above
        definition = ADK.definition_store.get_definition(agent_name_sym)

        # 3. Check definition.webhook_enabled
        unless definition.webhook_enabled
          logger.warn("Agent '#{agent_name_sym}' is not enabled for webhooks (webhook_enabled=false).")
          # Use 404 to avoid revealing agent existence if not webhook enabled
          halt 404, json({ status: :error, error_message: "Webhook endpoint not found for this agent." })
        end

        # 4. Perform Validation
        validator_config = definition.webhook_validator || webhook_config.global_validator
        secret = definition.webhook_secret || webhook_config.global_secret
        if validator_config
          validator_proc = validator_config.is_a?(Proc) ? validator_config : webhook_config.find_validator(validator_config)

          if validator_proc.nil?
            logger.error("Webhook validation failed for '#{agent_name_sym}': Validator '#{validator_config}' not found.")
            halt 500, json({ status: :error, error_message: "Internal Server Error: Validator configuration issue." })
          end

          begin
            is_valid = validator_proc.call(request, secret)
            unless is_valid
              logger.warn("Webhook validation failed for agent '#{agent_name_sym}'.")
              halt 401, json({ status: :error, error_message: "Unauthorized: Invalid request signature or credentials." })
            end
            logger.debug("Webhook validation successful for agent '#{agent_name_sym}'.")
          rescue StandardError => e
            logger.error("Error during webhook validation for '#{agent_name_sym}': #{e.message}")
            halt 500, json({ status: :error, error_message: "Internal Server Error during validation." })
          end
        else
          logger.debug("No validator configured for agent '#{agent_name_sym}', skipping validation.")
        end

        # 5. Perform Transformation (Required if webhook_enabled is true)
        transformer = definition.webhook_transformer
        unless transformer.is_a?(Proc)
          logger.error("Webhook configuration error for '#{agent_name_sym}': Missing webhook_transformer Proc.")
          halt 500, json({ status: :error, error_message: "Internal Server Error: Agent webhook configuration incomplete (transformer)." })
        end

        begin
          # Pass the parsed JSON body if available, otherwise the raw body string
          payload_for_transform = env['rack.input.json'] || raw_request_body
          transformed_user_input = transformer.call(payload_for_transform)
          logger.debug("Webhook payload transformed successfully for agent '#{agent_name_sym}'.")
        rescue ADK::WebhookConfigurationError => e 
          # Re-raise specific config errors to be caught by dedicated handler
          raise e 
        rescue StandardError => e
          logger.error("Error during webhook transformation for '#{agent_name_sym}': #{e.class} - #{e.message}")
          halt 500, json({ status: :error, error_message: "Internal Server Error during payload transformation." })
        end

        # 6. Extract Session ID (Required if webhook_enabled is true)
        extractor = definition.webhook_session_extractor
        unless extractor.is_a?(Proc)
          logger.error("Webhook configuration error for '#{agent_name_sym}': Missing webhook_session_extractor Proc.")
          halt 500, json({ status: :error, error_message: "Internal Server Error: Agent webhook configuration incomplete (session extractor)." })
        end

        begin
          # Pass the parsed JSON body if available, otherwise the raw body string
          payload_for_extract = env['rack.input.json'] || raw_request_body
          session_id = extractor.call(payload_for_extract)
          raise ADK::WebhookConfigurationError, "Session extractor must return a non-empty String session ID." unless session_id.is_a?(String) && !session_id.strip.empty?
          logger.debug("Webhook session ID extracted successfully for agent '#{agent_name_sym}': #{session_id}")
        rescue ADK::WebhookConfigurationError => e
           # Re-raise specific config errors to be caught by dedicated handler
          raise e
        rescue StandardError => e
          logger.error("Error during webhook session extraction for '#{agent_name_sym}': #{e.class} - #{e.message}")
          halt 500, json({ status: :error, error_message: "Internal Server Error during session ID extraction." })
        end

        # 7. Enqueue Job
        begin
          # TODO: Define ADK::WebhookJobWorker class
          # worker_class = ADK::WebhookJobWorker 
          worker_class_name = 'ADK::WebhookJobWorker' # Use string name for Sidekiq

          # Prepare session service config (assuming Redis for now based on user prompt)
          # We need the config used by the worker, not necessarily the instance itself.
          # ADK.redis_options provides the base Redis config hash.
          session_service_config = ADK.redis_options.dup
          # Optionally add type marker if multiple service types could be used?
          session_service_config[:type] = :redis # Example marker

          job_payload = {
            'agent_definition_name' => agent_name_sym.to_s, # Sidekiq args should be simple types
            'session_id' => session_id,
            'transformed_user_input' => transformed_user_input,
            'session_service_config' => session_service_config
          }

          # Use Sidekiq Client API directly
          job_id = Sidekiq::Client.push(
            'queue' => 'adk_webhooks', # TODO: Make queue name configurable?
            'class' => worker_class_name,
            'args' => [job_payload]
          )

          if job_id.nil?
             logger.error("Failed to enqueue webhook job for agent '#{agent_name_sym}': Sidekiq push returned nil.")
             halt 503, json({ status: :error, error_message: "Service Unavailable: Failed to queue background job." })
          end

          logger.info("Webhook job enqueued successfully for agent '#{agent_name_sym}'. Session: #{session_id}, Job ID: #{job_id}")

        rescue Redis::CannotConnectError, Sidekiq::Error => e # Catch Sidekiq/Redis errors
           logger.error("Failed to enqueue webhook job for agent '#{agent_name_sym}': #{e.class} - #{e.message}")
           halt 503, json({ status: :error, error_message: "Service Unavailable: Error connecting to job queue." })
        rescue StandardError => e
          logger.error("Unexpected error during job enqueuing for '#{agent_name_sym}': #{e.class} - #{e.message}")
          halt 500, json({ status: :error, error_message: "Internal Server Error during job queuing." })
        end

        # 8. Return 202 Accepted
        content_type :json
        status 202
        json({ status: :accepted, message: "Request for agent '#{agent_name_sym}' accepted and queued.", job_id: job_id })
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