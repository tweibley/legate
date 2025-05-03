# File: lib/adk/webhook_job_worker.rb
# frozen_string_literal: true

require 'sidekiq'
require 'adk' # Access ADK.logger, ADK.definition_store etc.
# Require necessary components the worker interacts with
require 'adk/agent'
require 'adk/session_service/redis' # Assuming Redis based on prompt
require 'adk/session_service/base'
require 'adk/errors'
require 'redis'

module ADK
  # Sidekiq worker responsible for processing agent tasks triggered by webhooks.
  class WebhookJobWorker
    include Sidekiq::Worker
    sidekiq_options queue: 'adk_webhooks', retry: 3 # Configure queue and retries

    def perform(job_payload)
      ADK.logger.info("WebhookJobWorker starting job: #{job_payload.inspect}")

      session_service = nil
      agent = nil
      definition = nil

      begin
        # 1. Parse Payload & Validate (Inside Begin)
        agent_name_sym = job_payload['agent_definition_name']&.to_sym
        session_id = job_payload['session_id']
        user_input = job_payload['transformed_user_input']
        session_service_config = job_payload['session_service_config']
        unless agent_name_sym && session_id && user_input && session_service_config
          # Log is good, but raise to signal failure to Sidekiq
          raise ArgumentError, "Invalid job payload: Missing required keys in #{job_payload.inspect}"
        end

        # 2. Instantiate Session Service
        service_type = session_service_config.fetch('type', 'redis').to_sym
        if service_type == :redis
          # Convert keys to symbols and remove :type
          redis_opts_sym = session_service_config.transform_keys(&:to_sym).reject { |k, _| k == :type }
          # Explicitly create Redis client instance using options from config
          begin
            redis_client = Redis.new(**redis_opts_sym)
            redis_client.ping # Verify connection early
          rescue Redis::BaseError => e
            ADK.logger.error("WebhookJobWorker: Failed to connect to Redis using config [#{redis_opts_sym}]: #{e.message}")
            raise # Re-raise connection error
          end
          # Pass the client instance using the keyword argument
          session_service = ADK::SessionService::Redis.new(redis_client: redis_client)
          ADK.logger.debug("WebhookJobWorker using RedisSessionService with options: #{redis_opts_sym}")
        else
          # Config error, likely non-retryable
          raise NotImplementedError, "Unsupported session service type in job config: #{service_type}"
        end

        # 3. Load Agent Definition
        definition_hash = ADK.config.definition_store.get_definition(agent_name_sym)
        unless definition_hash
          raise ADK::DefinitionStore::DefinitionNotFound, "Definition not found in store for :#{agent_name_sym}"
        end

        ADK.logger.debug("WebhookJobWorker loaded definition for: #{agent_name_sym}")

        # 4. Instantiate Agent
        in_memory_definition = ADK::GlobalDefinitionRegistry.find(agent_name_sym)
        unless in_memory_definition
          # This indicates the agent definition file wasn't loaded in the worker process
          # This is a critical configuration error.
          raise ADK::ConfigurationError,
                "In-memory definition for :#{agent_name_sym} not found in GlobalDefinitionRegistry within worker."
        end

        # --- Pass the initialized session service to the agent --- #
        agent = ADK::Agent.new(definition: in_memory_definition, session_service: session_service)
        ADK.logger.debug("WebhookJobWorker instantiated agent: #{agent.name}")

        # 5. Start Agent Runtime (Agent needs to be running to execute tasks)
        agent.start

        # 6. Call agent.run_task
        ADK.logger.info("WebhookJobWorker calling agent.run_task for session: #{session_id}")
        task_result = agent.run_task(
          session_id: session_id,
          user_input: user_input,
          session_service: session_service
        )

        # 7. Log Outcome
        result_content = task_result.is_a?(ADK::Event) ? task_result.content : task_result
        if result_content.is_a?(Hash) && result_content[:status] == :error
          ADK.logger.error("WebhookJobWorker: Agent task finished with error for session #{session_id}. Result: #{result_content.inspect}")
        else
          ADK.logger.info("WebhookJobWorker: Agent task finished successfully for session #{session_id}. Result: #{result_content.inspect}")
        end

      # --- Refined Error Handling ---
      rescue ArgumentError => e # Payload validation failed
        ADK.logger.error("WebhookJobWorker failed due to invalid payload: #{e.message}")
        raise # Re-raise ArgumentError: Non-retryable input error.
      rescue ADK::DefinitionStore::DefinitionNotFound => e
        ADK.logger.error("WebhookJobWorker failed: Agent definition '#{agent_name_sym}' not found. #{e.message}")
        raise # Re-raise DefinitionNotFound: Non-retryable if definition deleted.
      rescue NotImplementedError => e # Session Service type invalid
        ADK.logger.error("WebhookJobWorker failed: Configuration error - #{e.message}")
        raise # Re-raise NotImplementedError: Non-retryable config error.
      rescue Redis::CannotConnectError => e # Specific potentially retryable infra error
        ADK.logger.error("WebhookJobWorker failed: Cannot connect to Redis for session service. #{e.message}")
        raise # Re-raise - let Sidekiq handle retry based on Redis availability.
      rescue ADK::SessionError => e # Other potentially retryable session issues
        ADK.logger.error("WebhookJobWorker failed: Session service error for session '#{session_id}'. Error: #{e.message}")
        raise # Re-raise - let Sidekiq handle retry.
      rescue StandardError => e # Catch-all for unexpected errors during execution
        ADK.logger.error("WebhookJobWorker failed unexpectedly for agent '#{agent_name_sym}', session '#{session_id}': #{e.class} - #{e.message}")
        ADK.logger.error(e.backtrace.join("\n"))
        raise # Re-raise StandardError: Let Sidekiq handle retry for transient issues.
        # -----------------------------
      end
    end
  end
end
