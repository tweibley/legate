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
      agent_name_sym = nil
      session_id = nil

      begin
        agent_name_sym, session_id, user_input, session_service_config = validate_payload!(job_payload)
        execute_job(agent_name_sym, session_id, user_input, session_service_config)
      rescue ArgumentError => e
        handle_error(e, "WebhookJobWorker failed due to invalid payload: #{e.message}")
      rescue ADK::DefinitionStore::DefinitionNotFound => e
        handle_error(e, "WebhookJobWorker failed: Agent definition '#{agent_name_sym}' not found. #{e.message}")
      rescue NotImplementedError => e
        handle_error(e, "WebhookJobWorker failed: Configuration error - #{e.message}")
      rescue Redis::CannotConnectError => e
        handle_error(e, "WebhookJobWorker failed: Cannot connect to Redis for session service. #{e.message}")
      rescue ADK::SessionError => e
        handle_error(e, "WebhookJobWorker failed: Session service error for session '#{session_id}'. Error: #{e.message}")
      rescue StandardError => e
        handle_unexpected_error(e, agent_name_sym, session_id)
      end
    end

    private

    def execute_job(agent_name_sym, session_id, user_input, session_service_config)
      session_service = initialize_session_service(session_service_config)
      definition = load_agent_definition(agent_name_sym)

      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      ADK.logger.debug("WebhookJobWorker instantiated agent: #{agent.name}")

      agent.start
      run_task_and_log(agent, session_id, user_input, session_service)
    end

    def validate_payload!(job_payload)
      agent_name_sym = job_payload['agent_definition_name']&.to_sym
      session_id = job_payload['session_id']
      user_input = job_payload['transformed_user_input']
      session_service_config = job_payload['session_service_config']

      raise ArgumentError, "Invalid job payload: Missing required keys in #{job_payload.inspect}" unless agent_name_sym && session_id && user_input && session_service_config

      [agent_name_sym, session_id, user_input, session_service_config]
    end

    def initialize_session_service(session_service_config)
      service_type = session_service_config.fetch('type', 'redis').to_sym
      raise NotImplementedError, "Unsupported session service type: #{service_type}" unless service_type == :redis

      redis_opts = session_service_config.transform_keys(&:to_sym).reject { |k, _| k == :type }
      redis_client = create_redis_client(redis_opts)

      ADK.logger.debug("WebhookJobWorker using RedisSessionService with options: #{redis_opts}")
      ADK::SessionService::Redis.new(redis_client: redis_client)
    end

    def create_redis_client(redis_opts)
      client = Redis.new(**redis_opts)
      client.ping
      client
    rescue Redis::BaseError => e
      ADK.logger.error("WebhookJobWorker: Failed to connect to Redis using config [#{redis_opts}]: #{e.message}")
      raise
    end

    def load_agent_definition(agent_name_sym)
      raise ADK::DefinitionStore::DefinitionNotFound, "Definition not found in store for :#{agent_name_sym}" unless ADK.config.definition_store.get_definition(agent_name_sym)

      ADK.logger.debug("WebhookJobWorker loaded definition for: #{agent_name_sym}")
      fetch_in_memory_definition(agent_name_sym)
    end

    def fetch_in_memory_definition(agent_name_sym)
      in_memory_definition = ADK::GlobalDefinitionRegistry.find(agent_name_sym)
      unless in_memory_definition
        raise ADK::ConfigurationError,
              "In-memory definition for :#{agent_name_sym} not found in GlobalDefinitionRegistry within worker."
      end
      in_memory_definition
    end

    def run_task_and_log(agent, session_id, user_input, session_service)
      ADK.logger.info("WebhookJobWorker calling agent.run_task for session: #{session_id}")
      task_result = agent.run_task(
        session_id: session_id, user_input: user_input, session_service: session_service
      )
      log_result(task_result, session_id)
    end

    def log_result(task_result, session_id)
      result_content = task_result.is_a?(ADK::Event) ? task_result.content : task_result
      if result_content.is_a?(Hash) && result_content[:status] == :error
        ADK.logger.error("WebhookJobWorker: Agent task finished with error for session #{session_id}. Result: #{result_content.inspect}")
      else
        ADK.logger.info("WebhookJobWorker: Agent task finished successfully for session #{session_id}. Result: #{result_content.inspect}")
      end
    end

    def handle_error(error, message)
      ADK.logger.error(message)
      raise error
    end

    def handle_unexpected_error(error, agent_name_sym, session_id)
      ADK.logger.error("WebhookJobWorker failed unexpectedly for agent '#{agent_name_sym}', session '#{session_id}': #{error.class} - #{error.message}")
      ADK.logger.error(error.backtrace.join("\n"))
      raise error
    end
  end
end
