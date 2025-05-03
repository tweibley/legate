# File: lib/adk/webhook_job_worker.rb
# frozen_string_literal: true

require 'sidekiq'
require 'adk' # Access ADK.logger, ADK.definition_store etc.
# Require necessary components the worker interacts with
require 'adk/agent'
require 'adk/session_service/redis' # Assuming Redis based on prompt
require 'adk/session_service/base' 
require 'adk/errors'

module ADK
  # Sidekiq worker responsible for processing agent tasks triggered by webhooks.
  class WebhookJobWorker
    include Sidekiq::Worker
    sidekiq_options queue: 'adk_webhooks', retry: 3 # Configure queue and retries

    def perform(job_payload)
      ADK.logger.info("WebhookJobWorker starting job: #{job_payload.inspect}")

      # 1. Parse Payload
      agent_name_sym = job_payload['agent_definition_name']&.to_sym
      session_id = job_payload['session_id']
      user_input = job_payload['transformed_user_input']
      session_service_config = job_payload['session_service_config']

      unless agent_name_sym && session_id && user_input && session_service_config
        ADK.logger.error("WebhookJobWorker failed: Invalid job payload. Missing required keys.")
        # Consider raising an error to trigger Sidekiq retry or move to Dead Set
        raise ArgumentError, "Invalid job payload: #{job_payload.inspect}"
        return
      end

      session_service = nil
      agent = nil
      definition = nil

      begin
        # 2. Instantiate Session Service
        # Assuming Redis based on config structure used in listener
        service_type = session_service_config.fetch(:type, :redis).to_sym
        if service_type == :redis
          # Pass Redis connection options from config
          redis_opts = session_service_config.reject { |k, _| k == :type }
          session_service = ADK::SessionService::Redis.new(redis_opts)
          ADK.logger.debug("WebhookJobWorker using RedisSessionService with options: #{redis_opts}")
        else
          raise NotImplementedError, "Unsupported session service type in job config: #{service_type}"
        end

        # 3. Load Agent Definition
        definition = ADK.definition_store.get_definition(agent_name_sym)
        ADK.logger.debug("WebhookJobWorker loaded definition for: #{agent_name_sym}")

        # 4. Instantiate Agent
        # This might need adjustment depending on how Agent initialization evolves.
        # Assuming Agent.new can work with just a definition for task execution.
        # TODO: Verify Agent initialization strategy for workers.
        agent = ADK::Agent.new(definition: definition) # Pass definition instead of individual args
        ADK.logger.debug("WebhookJobWorker instantiated agent: #{agent.name}")

        # 5. Get/Create Session (Session service handles creation)
        # Ensure session exists - get_session likely doesn't create, need explicit create or ensure_session?
        # Let's assume `run_task` can handle session creation via the service if needed, or relies on pre-existence.
        # session = session_service.get_session(session_id: session_id)
        # raise StandardError, "Session not found by service: #{session_id}" unless session
        # For now, pass session_id directly to run_task as per current Agent#run_task signature.

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

      rescue ADK::DefinitionStore::DefinitionNotFound => e
        ADK.logger.error("WebhookJobWorker failed: Could not find definition for agent '#{agent_name_sym}'. Error: #{e.message}")
        # Non-retryable error for this job if definition is gone.
        raise # Re-raise to let Sidekiq handle retries/dead set based on config
      rescue ADK::SessionService::SessionError => e
        ADK.logger.error("WebhookJobWorker failed: Session service error for session '#{session_id}'. Error: #{e.message}")
        raise # Retryable?
      rescue NotImplementedError => e # Catch session service type error
         ADK.logger.error("WebhookJobWorker failed: #{e.message}")
         raise # Non-retryable config issue
      rescue StandardError => e
        ADK.logger.error("WebhookJobWorker failed unexpectedly for agent '#{agent_name_sym}', session '#{session_id}': #{e.class} - #{e.message}")
        ADK.logger.error(e.backtrace.join("\n"))
        raise # Re-raise standard errors for Sidekiq retry mechanism
      end
    end
  end
end 