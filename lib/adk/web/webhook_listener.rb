# File: lib/adk/web/webhook_listener.rb
# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'sidekiq' # For Sidekiq::Client.push
require 'adk' # To access ADK.config, ADK.logger, ADK.definition_store
require 'adk/errors' # For ADK::WebhookConfigurationError
require_relative '../global_definition_registry' # <<< Added require
require 'mustermann' # For path pattern matching

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

      # --- Instance Initialization ---
      def initialize(app = nil)
        super(app) # Call Sinatra::Base initializer
        setup_static_routes! # Setup routes on instance creation
      end
      # ---------------------------

      # --- Middleware/Hooks ---

      before do
        # Ensure request body is parsed as JSON if content type indicates it
        if request.content_type&.match?(%r{application/json}i)
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
        json({ status: :error, error_message: 'Agent definition not found.' })
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

      # Dynamic route handler using pattern matching
      post '*' do
        agent_name_sym = match_and_authorize_dynamic_route!

        logger.info("WebhookListener: Processing dynamic agent trigger for: #{agent_name_sym}")

        # Load agent definition
        definition_hash, in_memory_definition = fetch_agent_definition(agent_name_sym)

        # Read raw body *first* for validation purposes
        request.body.rewind
        raw_request_body = request.body.read
        request.body.rewind # Rewind again for potential JSON parsing or handler use

        # Validate request
        validate_webhook_request!(agent_name_sym, definition_hash, in_memory_definition)

        # Transform payload
        parsed_json_body = env['rack.input.json']
        payload_for_transform = parsed_json_body || raw_request_body
        transformed_user_input = transform_payload(agent_name_sym, in_memory_definition, payload_for_transform)

        # Extract Session ID
        session_id = extract_session_id(agent_name_sym, in_memory_definition, payload_for_transform)

        # Enqueue Job
        job_id = enqueue_webhook_job(agent_name_sym, session_id, transformed_user_input)

        # Return 202 Accepted
        content_type :json
        status 202
        json({ status: :accepted, message: "Request for agent '#{agent_name_sym}' accepted and queued.",
               job_id: job_id })
      end

      # Catch-all for undefined routes within the listener's base path
      not_found do
        content_type :json
        # Only set body if not already set by a specific halt
        if response.body.empty?
          json({ status: :error,
                 error_message: "Webhook route not found: #{request.request_method} #{request.path_info}" })
        end
        status 404 # Ensure status is 404
      end

      private

      def match_and_authorize_dynamic_route!
        webhook_config = ADK.config.webhooks
        configured_pattern = webhook_config.dynamic_agent_route_pattern
        pattern = Mustermann.new(configured_pattern, type: :sinatra)
        match_params = pattern.params(request.path_info)

        # Only proceed if the pattern matches
        unless match_params
          return pass # Didn't match dynamic pattern, try other routes (static, not_found)
        end

        # Pattern matched. Now check if handler enabled.
        unless webhook_config.enable_dynamic_agent_handler
          logger.warn('Webhook dynamic route matched, but handler is disabled.')
          halt 403, json({ status: :error, error_message: 'Dynamic agent webhooks are disabled.' }) # Explicit 403
        end

        # Handler enabled and pattern matched. Extract agent name.
        agent_name_param = match_params['agent_name']
        unless agent_name_param
          logger.error("Webhook dynamic route matched, but required 'agent_name' parameter missing in pattern or path.")
          # Consider this a server config error if name is expected but missing
          halt 500, json({ status: :error, error_message: 'Internal Server Error: Route configuration issue.' })
        end

        agent_name_param.to_sym
      end

      def fetch_agent_definition(agent_name_sym)
        store = ADK.config.definition_store
        raise ADK::ConfigurationError, 'Definition store not available via ADK.config.definition_store' unless store

        definition_hash = store.get_definition(agent_name_sym)
        in_memory_definition = ADK::GlobalDefinitionRegistry.find(agent_name_sym)

        unless in_memory_definition
          logger.error("WebhookListener: In-memory definition for :#{agent_name_sym} not found in GlobalDefinitionRegistry.")
          halt 500, json({ status: :error, error_message: 'Internal Server Error: Agent definition not loaded.' })
        end

        # --- Check webhook_enabled using the HASH from the store --- #
        unless definition_hash && definition_hash[:webhook_enabled]
          logger.warn("Agent '#{agent_name_sym}' is not enabled for webhooks (webhook_enabled=false or definition hash missing). Definition Hash: #{definition_hash.inspect}")
          halt 404, json({ status: :error, error_message: 'Webhook endpoint not found for this agent.' })
        end

        [definition_hash, in_memory_definition]
      end

      def validate_webhook_request!(agent_name_sym, definition_hash, in_memory_definition)
        webhook_config = ADK.config.webhooks
        validator_config = in_memory_definition.webhook_validator || webhook_config.global_validator
        secret = definition_hash[:webhook_secret] || webhook_config.global_secret

        return unless validator_config

        validator_proc = validator_config.is_a?(Proc) ? validator_config : webhook_config.find_validator(validator_config)

        if validator_proc.nil?
          logger.error("Webhook validation failed for '#{agent_name_sym}': Validator '#{validator_config}' not found.")
          halt 500, json({ status: :error, error_message: 'Internal Server Error: Validator configuration issue.' })
        end

        begin
          is_valid = validator_proc.call(request, secret)
          unless is_valid
            logger.warn("Webhook validation failed for agent '#{agent_name_sym}'.")
            halt 401, json({ status: :error, error_message: 'Unauthorized: Invalid request signature or credentials.' })
          end
          logger.debug("Webhook validation successful for agent '#{agent_name_sym}'.")
        rescue StandardError => e
          logger.error("Error during webhook validation for '#{agent_name_sym}': #{e.message}")
          halt 500, json({ status: :error, error_message: 'Internal Server Error during validation.' })
        end
      end

      def transform_payload(agent_name_sym, in_memory_definition, payload)
        transformer = in_memory_definition.webhook_transformer
        unless transformer.is_a?(Proc)
          logger.error("Webhook configuration error for '#{agent_name_sym}': Missing webhook_transformer Proc in in-memory definition.")
          halt 500, json({ status: :error, error_message: 'Internal Server Error: Agent webhook configuration incomplete (transformer).' })
        end

        transformer.call(payload)
      rescue ADK::WebhookConfigurationError => e
        raise e
      rescue StandardError => e
        logger.error("Error during webhook transformation for '#{agent_name_sym}': #{e.class} - #{e.message}")
        halt 500, json({ status: :error, error_message: 'Internal Server Error during payload transformation.' })
      end

      def extract_session_id(agent_name_sym, in_memory_definition, payload)
        extractor = in_memory_definition.webhook_session_extractor
        unless extractor.is_a?(Proc)
          logger.error("Webhook configuration error for '#{agent_name_sym}': Missing webhook_session_extractor Proc in in-memory definition.")
          halt 500, json({ status: :error, error_message: 'Internal Server Error: Agent webhook configuration incomplete (session extractor).' })
        end

        session_id = extractor.call(payload)
        raise ADK::WebhookConfigurationError, 'Session extractor must return a non-empty String session ID.' unless session_id.is_a?(String) && !session_id.strip.empty?

        session_id
      rescue ADK::WebhookConfigurationError => e
        raise e
      rescue StandardError => e
        logger.error("Error during webhook session extraction for '#{agent_name_sym}': #{e.class} - #{e.message}")
        halt 500, json({ status: :error, error_message: 'Internal Server Error during session ID extraction.' })
      end

      def enqueue_webhook_job(agent_name_sym, session_id, transformed_user_input)
        worker_class_name = 'ADK::WebhookJobWorker'
        session_service_config = ADK.redis_options.dup
        string_key_config = session_service_config.transform_keys(&:to_s)
        string_key_config['type'] = 'redis'

        job_payload = {
          'agent_definition_name' => agent_name_sym.to_s,
          'session_id' => session_id,
          'transformed_user_input' => transformed_user_input,
          'session_service_config' => string_key_config
        }

        job_id = Sidekiq::Client.push(
          'queue' => 'adk_webhooks',
          'class' => worker_class_name,
          'args' => [job_payload]
        )

        if job_id.nil?
          logger.error("Failed to enqueue webhook job for agent '#{agent_name_sym}': Sidekiq push returned nil.")
          halt 503, json({ status: :error, error_message: 'Service Unavailable: Failed to queue background job.' })
        end

        logger.info("Webhook job enqueued successfully for agent '#{agent_name_sym}'. Session: #{session_id}, Job ID: #{job_id}")
        job_id
      rescue Redis::CannotConnectError => e
        logger.error("Failed to enqueue webhook job (Redis Connect Error) for agent '#{agent_name_sym}': #{e.class} - #{e.message}")
        halt 503, json({ status: :error, error_message: 'Service Unavailable: Error connecting to job queue.' })
      rescue StandardError => e
        logger.error("Unexpected error during job enqueuing for '#{agent_name_sym}': #{e.class} - #{e.message}")
        halt 500, json({ status: :error, error_message: 'Internal Server Error during job queuing.' })
      end

      # --- Instance method to set up static routes ---
      def setup_static_routes!
        webhook_config = ADK.config.webhooks
        logger = ADK.logger # Use instance logger helper

        webhook_config.static_routes.each do |method_path, route_config|
          method, path = method_path.split(' ', 2)
          http_method = method.downcase.to_sym

          unless %i[get post put patch delete head options].include?(http_method)
            logger.error("WebhookListener: Invalid HTTP method '#{method}' specified for static route '#{path}'. Skipping.")
            next
          end
          unless route_config.handler.is_a?(Proc)
            logger.error("WebhookListener: Invalid handler (not a Proc) for static route '#{method_path}'. Skipping.")
            next
          end

          logger.debug("WebhookListener: Defining static route: #{http_method.upcase} #{path}")

          # Use Sinatra's instance-level routing DSL (get, post, etc.)
          self.class.send(http_method, path) do |*route_params|
            # Re-fetch config inside route block in case it changed?
            # Or rely on config captured during initialization?
            # Let's assume config is stable after init for simplicity.

            # --- Validation Logic ---
            # (Same as before, but now inside instance route block)
            current_validator_config = route_config.validator # Use captured route_config
            current_secret = route_config.secret
            if current_validator_config
              current_validator_proc = current_validator_config.is_a?(Proc) ? current_validator_config : webhook_config.find_validator(current_validator_config)
              if current_validator_proc.nil?
                logger.error("Static Route Validation Error [#{method_path}]: Validator '#{current_validator_config}' not found.")
                halt 500,
                     json({ status: :error,
                            error_message: 'Internal Server Error: Static route validator configuration issue.' })
              end
              begin
                is_valid = current_validator_proc.call(request, current_secret)
                unless is_valid
                  logger.warn("Static Route Validation Failed [#{method_path}]")
                  halt 401,
                       json({ status: :error,
                              error_message: 'Unauthorized: Invalid request signature or credentials.' })
                end
                logger.debug("Static Route Validation OK [#{method_path}]")
              rescue StandardError => e
                logger.error("Error during static route validation [#{method_path}]: #{e.message}")
                halt 500,
                     json({ status: :error, error_message: 'Internal Server Error during static route validation.' })
              end
            end
            # --- End Validation Logic ---

            # Execute the handler proc
            begin
              # Pass route params along with request to handler? Handler signature is just `call(request)` for now.
              route_config.handler.call(request)
            rescue StandardError => e
              logger.error("Error executing static route handler [#{method_path}]: #{e.class} - #{e.message}")
              logger.error(e.backtrace.join("\n"))
              halt 500, json({ status: :error, error_message: 'Internal Server Error in static route handler.' })
            end
          end
        end
      end
      # --- End instance method ---
    end
  end
end
