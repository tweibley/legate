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

      begin
        agent_name, session_id, user_input, service_config = validate_payload(job_payload)
        session_service = initialize_session_service(service_config)
        agent = initialize_agent(agent_name, session_service)

        execute_task(agent, session_id, user_input, session_service)

      rescue ArgumentError => e
        ADK.logger.error("WebhookJobWorker failed due to invalid payload: #{e.message}")
        raise
      rescue ADK::DefinitionStore::DefinitionNotFound => e
        ADK.logger.error("WebhookJobWorker failed: Agent definition not found. #{e.message}")
        raise
      rescue NotImplementedError => e
        ADK.logger.error("WebhookJobWorker failed: Configuration error - #{e.message}")
        raise
      rescue Redis::CannotConnectError => e
        ADK.logger.error("WebhookJobWorker failed: Cannot connect to Redis for session service. #{e.message}")
        raise
      rescue ADK::SessionError => e
        ADK.logger.error("WebhookJobWorker failed: Session service error for session '#{session_id}'. Error: #{e.message}")
        raise
      rescue StandardError => e
        ADK.logger.error("WebhookJobWorker failed unexpectedly: #{e.class} - #{e.message}")
        ADK.logger.error(e.backtrace.join("\n"))
        raise
      end
    end

    private

    def validate_payload(payload)
      agent_name = payload['agent_definition_name']&.to_sym
      session_id = payload['session_id']
      user_input = payload['transformed_user_input']
      config = payload['session_service_config']

      unless agent_name && session_id && user_input && config
        raise ArgumentError, "Invalid job payload: Missing required keys in #{payload.inspect}"
      end

      [agent_name, session_id, user_input, config]
    end

    def initialize_session_service(config)
      service_type = config.fetch('type', 'redis').to_sym
      unless service_type == :redis
        raise NotImplementedError, "Unsupported session service type in job config: #{service_type}"
      end

      redis_opts = config.transform_keys(&:to_sym).reject { |k, _| k == :type }

      begin
        redis_client = Redis.new(**redis_opts)
        redis_client.ping
      rescue Redis::BaseError => e
        ADK.logger.error("WebhookJobWorker: Failed to connect to Redis using config [#{redis_opts}]: #{e.message}")
        raise
      end

      ADK.logger.debug("WebhookJobWorker using RedisSessionService with options: #{redis_opts}")
      ADK::SessionService::Redis.new(redis_client: redis_client)
    end

    def initialize_agent(agent_name, session_service)
      unless ADK.config.definition_store.get_definition(agent_name)
        raise ADK::DefinitionStore::DefinitionNotFound, "Definition not found in store for :#{agent_name}"
      end

      ADK.logger.debug("WebhookJobWorker loaded definition for: #{agent_name}")

      definition = ADK::GlobalDefinitionRegistry.find(agent_name)
      unless definition
        raise ADK::ConfigurationError,
              "In-memory definition for :#{agent_name} not found in GlobalDefinitionRegistry within worker."
      end

      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      ADK.logger.debug("WebhookJobWorker instantiated agent: #{agent.name}")
      agent.start
      agent
    end

    def execute_task(agent, session_id, user_input, session_service)
      ADK.logger.info("WebhookJobWorker calling agent.run_task for session: #{session_id}")

      task_result = agent.run_task(
        session_id: session_id,
        user_input: user_input,
        session_service: session_service
      )

      log_result(session_id, task_result)
    end

    def log_result(session_id, result)
      content = result.is_a?(ADK::Event) ? result.content : result

      if content.is_a?(Hash) && content[:status] == :error
        ADK.logger.error("WebhookJobWorker: Agent task finished with error for session #{session_id}. Result: #{content.inspect}")
      else
        ADK.logger.info("WebhookJobWorker: Agent task finished successfully for session #{session_id}. Result: #{content.inspect}")
      end
    end
  end
end
