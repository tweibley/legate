# File: lib/legate/web/webhook_listener.rb
# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/custom_logger' # For `helpers Sinatra::CustomLogger` (no longer autoloaded in sinatra-contrib 4)
require 'json'
require 'concurrent'
require 'securerandom'
require 'legate' # To access Legate.config, Legate.logger
require 'legate/errors' # For Legate::WebhookConfigurationError
require_relative '../global_definition_registry'
require 'mustermann' # For path pattern matching

module Legate
  module Web
    # Minimal Rack application (using Sinatra) to listen for incoming webhooks.
    # Intended to be mounted within the main Legate::Web::App or run standalone.
    class WebhookListener < Sinatra::Base
      helpers Sinatra::CustomLogger # Use Legate.logger

      MAX_REQUEST_BODY_SIZE = 10 * 1024 * 1024 # 10 MB

      configure do
        set :logger, Legate.logger
        # Webhooks arrive from external services with arbitrary Host headers, so
        # permit all hosts (Sinatra 4 / rack-protection 4 enable Host
        # authorization by default, which would otherwise 403 them).
        set :host_authorization, { permitted_hosts: [] }
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
        env['webhook.request_id'] = SecureRandom.uuid

        # Reject oversized request bodies to prevent memory exhaustion
        content_length = request.content_length.to_i
        halt 413, json({ status: :error, error_message: 'Request body too large' }) if content_length > MAX_REQUEST_BODY_SIZE

        # Ensure request body is parsed as JSON if content type indicates it
        if request.content_type&.match?(%r{application/json}i)
          request.body.rewind
          begin
            raw_body = request.body.read(MAX_REQUEST_BODY_SIZE + 1)
            halt 413, json({ status: :error, error_message: 'Request body too large' }) if raw_body && raw_body.bytesize > MAX_REQUEST_BODY_SIZE
            # Store parsed body in rack env for handlers to access
            env['rack.input.json'] = JSON.parse(raw_body || '')
          rescue JSON::ParserError => e
            request_id = env['webhook.request_id']
            logger.warn("WebhookListener [#{request_id}]: Invalid JSON received: #{e.message}")
            halt 400, json({ status: :error, error_message: 'Invalid JSON format', request_id: request_id })
          ensure
            request.body.rewind # Ensure body is readable again for potential validation
          end
        end
      end

      # --- Error Handling ---

      error Legate::WebhookConfigurationError do
        e = env['sinatra.error']
        request_id = env['webhook.request_id']
        logger.warn("Webhook Configuration Error [#{request_id}]: #{e.message}")
        content_type :json
        status 400
        json({ status: :error, error_message: "Configuration Error: #{e.message}", request_id: request_id })
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

      error StandardError do
        e = env['sinatra.error']
        request_id = env['webhook.request_id']
        logger.error("WebhookListener Internal Error [#{request_id}]: #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        content_type :json
        status 500
        json({ status: :error, error_message: 'Internal Server Error', request_id: request_id })
      end

      # --- Routing ---

      # Dynamic route handler using pattern matching
      post '*' do
        webhook_config = Legate.config.webhooks
        agent_name_sym = nil

        # Match request path against configured pattern
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
        if agent_name_param
          # Validate against registered definitions before converting to Symbol
          # to prevent Symbol table exhaustion from arbitrary URL paths
          registered = Legate::GlobalDefinitionRegistry.all
          unless registered.keys.map(&:to_s).include?(agent_name_param.to_s)
            logger.warn("WebhookListener: Unknown agent '#{agent_name_param}' in webhook URL")
            halt 404, json({ status: :error, error_message: 'Agent not found' })
          end
          agent_name_sym = agent_name_param.to_sym
        else
          logger.error("Webhook dynamic route matched, but required 'agent_name' parameter missing in pattern or path.")
          # Consider this a server config error if name is expected but missing
          halt 500, json({ status: :error, error_message: 'Internal Server Error: Route configuration issue.' })
        end

        # --- Handler Logic (Agent name confirmed) ---
        # Read raw body *first* for validation purposes
        request.body.rewind
        raw_request_body = request.body.read
        request.body.rewind # Rewind again for potential JSON parsing or handler use

        parsed_json_body = env['rack.input.json'] # Parsed by 'before' hook if Content-Type was JSON

        logger.info("WebhookListener: Processing dynamic agent trigger for: #{agent_name_sym}")

        # Load agent definition from GlobalDefinitionRegistry
        in_memory_definition = Legate::GlobalDefinitionRegistry.find(agent_name_sym)

        unless in_memory_definition
          logger.error("WebhookListener: Definition for :#{agent_name_sym} not found in GlobalDefinitionRegistry.")
          halt 500, json({ status: :error, error_message: 'Internal Server Error: Agent definition not loaded.' })
        end

        # Check webhook_enabled on the definition object
        unless in_memory_definition.webhook_enabled
          logger.warn("Agent '#{agent_name_sym}' is not enabled for webhooks (webhook_enabled=false).")
          halt 404, json({ status: :error, error_message: 'Webhook endpoint not found for this agent.' })
        end

        # Perform Validation
        validator_config = in_memory_definition.webhook_validator || webhook_config.global_validator
        # Use agent secret, falling back to global secret if available
        secret = in_memory_definition.webhook_secret || webhook_config.global_secret
        if validator_config
          validator_proc = validator_config.is_a?(Proc) ? validator_config : webhook_config.find_validator(validator_config)

          if validator_proc.nil?
            logger.error("Webhook validation failed for '#{agent_name_sym}': Validator '#{validator_config}' not found.")
            halt 500, json({ status: :error, error_message: 'Internal Server Error: Validator configuration issue.' })
          end

          begin
            is_valid = validator_proc.call(request, secret)
            unless is_valid
              logger.warn("Webhook validation failed for agent '#{agent_name_sym}'.")
              halt 401,
                   json({ status: :error, error_message: 'Unauthorized: Invalid request signature or credentials.' })
            end
            logger.debug("Webhook validation successful for agent '#{agent_name_sym}'.")
          rescue StandardError => e
            logger.error("Error during webhook validation for '#{agent_name_sym}': #{e.message}")
            halt 500, json({ status: :error, error_message: 'Internal Server Error during validation.' })
          end
        else
          logger.debug("No validator configured for agent '#{agent_name_sym}', skipping validation.")
        end

        # 5. Perform Transformation (Required if webhook_enabled is true)
        # --- USE IN-MEMORY DEFINITION FOR PROC --- #
        transformer = in_memory_definition.webhook_transformer
        unless transformer.is_a?(Proc)
          logger.error("Webhook configuration error for '#{agent_name_sym}': Missing webhook_transformer Proc in in-memory definition.")
          halt 500,
               json({ status: :error,
                      error_message: 'Internal Server Error: Agent webhook configuration incomplete (transformer).' })
        end

        begin
          # Pass the parsed JSON body if available, otherwise the raw body string
          payload_for_transform = parsed_json_body || raw_request_body
          transformed_user_input = transformer.call(payload_for_transform)
          logger.debug("Webhook payload transformed successfully for agent '#{agent_name_sym}'.")
        rescue Legate::WebhookConfigurationError => e
          # Re-raise specific config errors to be caught by dedicated handler
          raise e
        rescue StandardError => e
          logger.error("Error during webhook transformation for '#{agent_name_sym}': #{e.class} - #{e.message}")
          halt 500, json({ status: :error, error_message: 'Internal Server Error during payload transformation.' })
        end

        # 6. Extract Session ID (Required if webhook_enabled is true)
        # --- USE IN-MEMORY DEFINITION FOR PROC --- #
        extractor = in_memory_definition.webhook_session_extractor
        unless extractor.is_a?(Proc)
          logger.error("Webhook configuration error for '#{agent_name_sym}': Missing webhook_session_extractor Proc in in-memory definition.")
          halt 500,
               json({ status: :error,
                      error_message: 'Internal Server Error: Agent webhook configuration incomplete (session extractor).' })
        end

        begin
          # Pass the parsed JSON body if available, otherwise the raw body string
          payload_for_extract = parsed_json_body || raw_request_body
          session_id = extractor.call(payload_for_extract)
          unless session_id.is_a?(String) && !session_id.strip.empty?
            raise Legate::WebhookConfigurationError,
                  'Session extractor must return a non-empty String session ID.'
          end

          logger.debug("Webhook session ID extracted successfully for agent '#{agent_name_sym}': #{session_id}")
        rescue Legate::WebhookConfigurationError => e
          # Re-raise specific config errors to be caught by dedicated handler
          raise e
        rescue StandardError => e
          logger.error("Error during webhook session extraction for '#{agent_name_sym}': #{e.class} - #{e.message}")
          halt 500, json({ status: :error, error_message: 'Internal Server Error during session ID extraction.' })
        end

        # 7. Spawn threaded task
        begin
          task_id = SecureRandom.uuid
          session_service = Legate.config.session_service

          # Ensure session exists in the shared service
          existing = session_service.get_session(session_id: session_id)
          unless existing
            session_service.create_session(
              app_name: agent_name_sym.to_s,
              user_id: 'webhook',
              session_id: session_id
            )
          end

          Concurrent::Promises.future do
            definition = Legate::GlobalDefinitionRegistry.find(agent_name_sym)
            agent = Legate::Agent.new(definition: definition, session_service: session_service)
            agent.start
            agent.run_task(session_id: session_id, user_input: transformed_user_input, session_service: session_service)
          rescue StandardError => e
            Legate.logger.error("Webhook agent task failed for '#{agent_name_sym}': #{e.class} - #{e.message}")
            Legate.logger.error(e.backtrace&.first(5)&.join("\n"))
          end

          logger.info("Webhook task spawned for agent '#{agent_name_sym}'. Session: #{session_id}, Task ID: #{task_id}")
        rescue StandardError => e
          logger.error("Unexpected error spawning webhook task for '#{agent_name_sym}': #{e.class} - #{e.message}")
          halt 500, json({ status: :error, error_message: 'Internal Server Error during task spawning.' })
        end

        # 8. Return 202 Accepted
        content_type :json
        status 202
        json({ status: :accepted, message: "Request for agent '#{agent_name_sym}' accepted and queued.",
               task_id: task_id })
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

      # --- Instance method to set up static routes ---
      def setup_static_routes!
        webhook_config = Legate.config.webhooks
        logger = Legate.logger # Use instance logger helper

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
