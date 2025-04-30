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

      # Helper method to convert a hash with symbol keys to string keys
      private def stringify_hash_keys(hash)
        hash.transform_keys(&:to_s)
      end

      # Overrides ADK::Tool#perform_execution to enqueue the Sidekiq job.
      # @param params [Hash] The validated parameters.
      # @param context [ADK::ToolContext] The execution context.
      # @return [Hash] { status: :pending, job_id: ... } or { status: :error, ... }
      private def perform_execution(params, context)
        worker_class = sidekiq_worker_class
        job_args = prepare_job_arguments(params, context)
        job_options = sidekiq_job_options

        unless worker_class && worker_class.respond_to?(:perform_async)
          msg = "sidekiq_worker_class not defined or invalid for tool '#{name}'."
          ADK.logger.error(msg)
          raise ADK::ToolError, msg
        end

        ADK.logger.info("Enqueuing Sidekiq job for worker '#{worker_class.name}' for tool '#{name}'.")
        ADK.logger.debug("Job Args: #{job_args.inspect}")
        ADK.logger.debug("Job Options: #{job_options.inspect}")

        begin
          # Convert any symbol keys in job arguments to strings for JSON serialization
          job_args = job_args.map do |arg|
            arg.is_a?(Hash) ? stringify_hash_keys(arg) : arg
          end

          # Use perform_async to enqueue the job
          jid = worker_class.set(job_options).perform_async(*job_args)

          unless jid
            msg = "Failed to enqueue Sidekiq job for '#{name}'. perform_async returned nil."
            ADK.logger.error(msg)
            raise ADK::ToolError, msg
          end

          ADK.logger.info("Successfully enqueued Sidekiq job '#{jid}' for tool '#{name}'. Task is pending.")
          { status: :pending, job_id: jid }
        rescue Redis::BaseError => e # Catch specific Redis errors
          msg = "Failed to enqueue job for tool '#{name}': Could not connect to Redis. #{e.message}"
          ADK.logger.error(msg)
          raise ADK::ToolError, msg
        rescue StandardError => e
          # Catch other unexpected errors during enqueueing
          msg = "Unexpected error enqueuing Sidekiq job for tool '#{name}': #{e.class} - #{e.message}"
          ADK.logger.error(msg)
          ADK.logger.error(e.backtrace.first(5).join("\n"))
          raise ADK::ToolError, msg # Wrap unexpected errors
        end
      end

      # --- Static Helpers for Workers to Store Status/Results --- #

      # Helper method for Sidekiq workers to call *at the beginning* of their perform method
      # to indicate the job has started processing.
      # @param jid [String] The Job ID (available inside the worker).
      # @param redis_options [Hash] Redis connection options (optional, uses ADK defaults if nil).
      def self.store_job_pending(jid, redis_options = nil)
        redis = Redis.new(redis_options || ADK.redis_options)
        key = "#{JOB_RESULT_REDIS_PREFIX}#{jid}"
        # Store pending status hash. Use the same TTL as results.
        result_data = { status: :pending, message: "Job processing started." }
        redis.setex(key, JOB_RESULT_TTL, result_data.to_json)
        ADK.logger.debug("Stored pending status for job #{jid} at key #{key}")
      rescue StandardError => e
        ADK.logger.error("Failed to store pending status for job #{jid}: #{e.class} - #{e.message}")
        # Log but don't raise, allow job processing to continue if possible.
      ensure
        redis&.close
      end

      # Helper method for Sidekiq workers to call upon completion to store their results in Redis.
      # @param jid [String] The Job ID (available inside the worker).
      # @param result [Object] The result data (must be JSON-serializable).
      # @param redis_options [Hash] Redis connection options (optional, uses ADK defaults if nil).
      def self.store_job_result(jid, result, redis_options = nil)
        redis = Redis.new(redis_options || ADK.redis_options)
        key = "#{JOB_RESULT_REDIS_PREFIX}#{jid}"
        # Store result hash including status
        result_data = { status: :success, result: result }
        redis.setex(key, JOB_RESULT_TTL, result_data.to_json)
        ADK.logger.debug("Stored successful result for job #{jid} at key #{key}")
      rescue StandardError => e
        ADK.logger.error("Failed to store result for job #{jid}: #{e.class} - #{e.message}")
        # Don't raise, just log the error. The job itself succeeded.
      ensure
        redis&.close
      end

      # Helper method for Sidekiq workers to call upon failure to store error information.
      # @param jid [String] The Job ID.
      # @param error_message [String] The error message.
      # @param error_class [String] The class name of the error (optional).
      # @param redis_options [Hash] Redis connection options (optional, uses ADK defaults if nil).
      def self.store_job_error(jid, error_message, error_class = 'StandardError', redis_options = nil)
        redis = Redis.new(redis_options || ADK.redis_options)
        key = "#{JOB_RESULT_REDIS_PREFIX}#{jid}"
        # Store error hash including status
        result_data = { status: :error, error_message: "#{error_class}: #{error_message}" }
        redis.setex(key, JOB_RESULT_TTL, result_data.to_json)
        ADK.logger.debug("Stored error result for job #{jid} at key #{key}")
      rescue StandardError => e
        ADK.logger.error("Failed to store error for job #{jid}: #{e.class} - #{e.message}")
      ensure
        redis&.close
      end
    end
  end
end
