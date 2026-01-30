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

      perform_job_logic(job_payload)
    rescue ArgumentError => e
      ADK.logger.error("WebhookJobWorker failed due to invalid payload: #{e.message}")
      raise
    rescue ADK::DefinitionStore::DefinitionNotFound => e
      ADK.logger.error("WebhookJobWorker failed: Agent definition '#{job_payload['agent_definition_name']}' not found. #{e.message}")
      raise
    rescue NotImplementedError => e
      ADK.logger.error("WebhookJobWorker failed: Configuration error - #{e.message}")
      raise
    rescue Redis::CannotConnectError => e
      ADK.logger.error("WebhookJobWorker failed: Cannot connect to Redis for session service. #{e.message}")
      raise
    rescue ADK::SessionError => e
      ADK.logger.error("WebhookJobWorker failed: Session service error for session '#{job_payload['session_id']}'. Error: #{e.message}")
      raise
    rescue StandardError => e
      ADK.logger.error("WebhookJobWorker failed unexpectedly for agent '#{job_payload['agent_definition_name']}', session '#{job_payload['session_id']}': #{e.class} - #{e.message}")
      ADK.logger.error(e.backtrace.join("\n"))
      raise
    end

    private

    def perform_job_logic(job_payload)
      payload = validate_payload!(job_payload)
      session_service = initialize_session_service(payload[:session_service_config])
      agent = setup_agent(payload[:agent_name], session_service)

      agent.start
      execute_task(agent, payload[:session_id], payload[:user_input], session_service)
    end

    def validate_payload!(job_payload)
      agent_name = job_payload['agent_definition_name']&.to_sym
      session_id = job_payload['session_id']
      user_input = job_payload['transformed_user_input']
      config = job_payload['session_service_config']

      raise ArgumentError, "Invalid job payload: Missing required keys in #{job_payload.inspect}" unless agent_name && session_id && user_input && config

      {
        agent_name: agent_name,
        session_id: session_id,
        user_input: user_input,
        session_service_config: config
      }
    end

    def initialize_session_service(config)
      service_type = config.fetch('type', 'redis').to_sym
      raise NotImplementedError, "Unsupported session service type in job config: #{service_type}" unless service_type == :redis

      redis_opts = config.transform_keys(&:to_sym).reject { |k, _| k == :type }

      begin
        redis_client = Redis.new(**redis_opts)
        redis_client.ping
      rescue Redis::BaseError => e
        ADK.logger.error("WebhookJobWorker: Failed to connect to Redis using config [#{redis_opts}]: #{e.message}")
        raise
      end

      ADK::SessionService::Redis.new(redis_client: redis_client).tap do
        ADK.logger.debug("WebhookJobWorker using RedisSessionService with options: #{redis_opts}")
      end
    end

    def setup_agent(agent_name, session_service)
      # Validate existence in store
      raise ADK::DefinitionStore::DefinitionNotFound, "Definition not found in store for :#{agent_name}" unless ADK.config.definition_store.get_definition(agent_name)

      ADK.logger.debug("WebhookJobWorker loaded definition for: #{agent_name}")

      # Validate existence in registry
      definition = ADK::GlobalDefinitionRegistry.find(agent_name)
      raise ADK::ConfigurationError, "In-memory definition for :#{agent_name} not found in GlobalDefinitionRegistry within worker." unless definition

      ADK::Agent.new(definition: definition, session_service: session_service).tap do |agent|
        ADK.logger.debug("WebhookJobWorker instantiated agent: #{agent.name}")
      end
    end

    def execute_task(agent, session_id, user_input, session_service)
      ADK.logger.info("WebhookJobWorker calling agent.run_task for session: #{session_id}")

      result = agent.run_task(
        session_id: session_id,
        user_input: user_input,
        session_service: session_service
      )

      log_result(result, session_id)
    end

    def log_result(task_result, session_id)
      content = task_result.is_a?(ADK::Event) ? task_result.content : task_result

      if content.is_a?(Hash) && content[:status] == :error
        ADK.logger.error("WebhookJobWorker: Agent task finished with error for session #{session_id}. Result: #{content.inspect}")
      else
        ADK.logger.info("WebhookJobWorker: Agent task finished successfully for session #{session_id}. Result: #{content.inspect}")
      end
    end
  end
end
