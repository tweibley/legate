# File: lib/adk/tools/base_async_job_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative '../error'
require 'sidekiq'
require 'redis' # For storing/retrieving results
require 'json' # For storing/retrieving results

module ADK
  module Tools
    # Abstract base class for tools that initiate asynchronous background tasks via Sidekiq.
    class BaseAsyncJobTool < ADK::Tool
      # Description for this base tool (primarily for informational purposes)
      tool_description "Base class for tools that initiate long-running tasks via Sidekiq background jobs. Subclasses must implement `sidekiq_worker_class` and `prepare_job_arguments`. Use 'check_job_status' tool to retrieve results."

      # --- Job Result Handling Configuration ---
      # Prefix for Redis keys used to store job results.
      JOB_RESULT_REDIS_PREFIX = 'adk:job_result:'
      # Expiration time for result keys in Redis (seconds). 1 hour default.
      JOB_RESULT_TTL = 3600
      # --- End Job Result Handling ---

      # Subclasses MUST override this method to return the Sidekiq Worker class
      # that should be executed.
      # @return [Class] The Sidekiq Worker class (must include Sidekiq::Worker and respond to #perform).
      def sidekiq_worker_class
        raise NotImplementedError, "#{self.class.name} must implement #sidekiq_worker_class"
      end

      # Subclasses CAN override this method to customize Sidekiq job options.
      # See: https://github.com/sidekiq/sidekiq/wiki/Job-Options
      # @return [Hash] Options hash for the Sidekiq job (e.g., { 'queue' => 'critical', 'retry' => 1 }).
      def sidekiq_job_options
        {
          'queue' => 'default', # Default Sidekiq queue
          'retry' => 3          # Default retry attempts
        }
      end

      # Subclasses MUST override this method to prepare the arguments
      # for the Sidekiq worker's perform method based on the ADK tool's parameters and context.
      # Note: Arguments must be simple types serializable to JSON (strings, numbers, bools, arrays, hashes).
      # @param params [Hash] The validated parameters passed to the ADK tool.
      # @param context [ADK::ToolContext] Contextual information (session_id, etc.).
      # @return [Array] An array of arguments to be passed to the worker's perform method.
      def prepare_job_arguments(params, context)
        raise NotImplementedError, "#{self.class.name} must implement #prepare_job_arguments(params, context)"
      end

      private

      # Helper method to convert a hash with symbol keys to string keys
      def stringify_hash_keys(hash)
        hash.transform_keys(&:to_s)
      end

      # Overrides ADK::Tool#perform_execution to enqueue the Sidekiq job.
      # @param params [Hash] The validated parameters.
      # @param context [ADK::ToolContext] The execution context.
      # @return [Hash] { status: :pending, job_id: ... } or { status: :error, ... }
      def perform_execution(params, context)
        worker_class = validate_worker_class!
        job_args = prepare_job_arguments(params, context)
        job_options = sidekiq_job_options

        log_job_enqueue(worker_class, job_args, job_options)
        enqueue_job(worker_class, job_args, job_options)
      end

      def validate_worker_class!
        worker_class = sidekiq_worker_class
        unless worker_class && worker_class.respond_to?(:perform_async)
          msg = "sidekiq_worker_class not defined or invalid for tool '#{name}'."
          ADK.logger.error(msg)
          raise ADK::ToolError, msg
        end
        worker_class
      end

      def log_job_enqueue(worker_class, job_args, job_options)
        ADK.logger.info("Enqueuing Sidekiq job for worker '#{worker_class.name}' for tool '#{name}'.")
        ADK.logger.debug("Job Args: #{job_args.inspect}")
        ADK.logger.debug("Job Options: #{job_options.inspect}")
      end

      def enqueue_job(worker_class, raw_job_args, job_options)
        job_args = raw_job_args.map do |arg|
          arg.is_a?(Hash) ? stringify_hash_keys(arg) : arg
        end

        jid = worker_class.set(job_options).perform_async(*job_args)
        raise_if_enqueue_failed(jid)

        ADK.logger.info("Successfully enqueued Sidekiq job '#{jid}' for tool '#{name}'. Task is pending.")
        { status: :pending, job_id: jid }
      rescue Redis::BaseError => error
        handle_redis_error(error)
      rescue StandardError => error
        handle_generic_error(error)
      end

      def raise_if_enqueue_failed(jid)
        return if jid

        msg = "Failed to enqueue Sidekiq job for '#{name}'. perform_async returned nil."
        ADK.logger.error(msg)
        raise ADK::ToolError, msg
      end

      def handle_redis_error(error)
        msg = "Failed to enqueue job for tool '#{name}': Could not connect to Redis. #{error.message}"
        ADK.logger.error(msg)
        raise ADK::ToolError, msg
      end

      def handle_generic_error(error)
        msg = "Unexpected error enqueuing Sidekiq job for tool '#{name}': #{error.class} - #{error.message}"
        ADK.logger.error(msg)
        ADK.logger.error(error.backtrace.first(5).join("\n"))
        raise ADK::ToolError, msg
      end

      # --- Static Helpers for Workers to Store Status/Results --- #

      public

      # Helper for Sidekiq workers to indicate job started processing.
      # @param jid [String] Job ID
      # @param redis_options [Hash] Redis options (optional)
      def self.store_job_pending(jid, redis_options = nil)
        store_in_redis(jid, { status: :pending, message: 'Job processing started.' }, redis_options)
      end

      # Helper for Sidekiq workers to store results in Redis.
      # @param jid [String] Job ID
      # @param result [Object] Result data (JSON-serializable)
      # @param redis_options [Hash] Redis options (optional)
      def self.store_job_result(jid, result, redis_options = nil)
        store_in_redis(jid, { status: :success, result: result }, redis_options)
      end

      # Helper for Sidekiq workers to store error info.
      # @param jid [String] Job ID
      # @param error_message [String] Error message
      # @param error_class [String] Error class name
      # @param redis_options [Hash] Redis options (optional)
      def self.store_job_error(jid, error_message, error_class = 'StandardError', redis_options = nil)
        store_in_redis(jid, { status: :error, error_message: "#{error_class}: #{error_message}" }, redis_options)
      end

      def self.store_in_redis(jid, data, redis_options)
        redis = Redis.new(redis_options || ADK.redis_options)
        key = "#{JOB_RESULT_REDIS_PREFIX}#{jid}"
        redis.setex(key, JOB_RESULT_TTL, data.to_json)
        ADK.logger.debug("Stored #{data[:status]} for job #{jid} at key #{key}")
      rescue StandardError => e
        ADK.logger.error("Failed to store #{data[:status]} for job #{jid}: #{e.class} - #{e.message}")
      ensure
        redis&.close
      end
      private_class_method :store_in_redis
    end
  end
end
