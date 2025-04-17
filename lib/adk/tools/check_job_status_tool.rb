# File: lib/adk/tools/check_job_status_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative '../error'
require 'sidekiq/api' # For checking job status
require 'redis'       # For retrieving results
require 'json'        # For parsing results

module ADK
  module Tools
    # A built-in tool to check the status and retrieve results for a Sidekiq job
    # initiated by an ADK tool.
    class CheckJobStatusTool < ADK::Tool
      define_metadata(
        name: :check_job_status,
        description: 'Checks the status and retrieves the result of a previously started background job (Sidekiq) using its ID.',
        parameters: {
          job_id: {
            type: :string,
            description: 'The ID of the job to check status for',
            required: true
          }
        }
      )

      def initialize(**options)
        super(**options)
      end

      private

      # @param params [Hash] Must contain :job_id.
      # @param _context [ADK::ToolContext, nil] The execution context (unused here).
      # @return [Hash] { status: :pending/:success/:error, ... }
      def perform_execution(params, _context)
        job_id = params[:job_id]
        return { status: :error, error_message: 'Missing required parameter: job_id' } unless job_id

        begin
          redis = Redis.new(ADK.redis_options)
          result_key = "#{ADK::Tools::BaseAsyncJobTool::JOB_RESULT_REDIS_PREFIX}#{job_id}"

          # First check Redis for completed results
          stored_result = redis.get(result_key)
          if stored_result
            begin
              parsed_result = JSON.parse(stored_result, symbolize_names: true)
              if parsed_result.is_a?(Hash) && parsed_result[:status]
                # Ensure status is a symbol
                parsed_result[:status] = parsed_result[:status].to_sym
                return parsed_result
              end
            rescue JSON::ParserError
              ADK.logger.error("Failed to parse stored JSON result for job #{job_id}: #{stored_result}")
            end
          end

          # If no valid result in Redis, check Sidekiq status
          status = check_sidekiq_status(job_id)
          case status
          when :pending
            {
              status: :pending,
              job_id: job_id,
              message: "Job is queued or currently running."
            }
          when :failed
            {
              status: :error,
              error_message: "Job has failed (found in Dead Set)."
            }
          when :completed_or_disappeared
            {
              status: :error,
              error_message: "Job result is unavailable. The job may have completed without storing a result, or the job ID may be invalid."
            }
          end
        rescue Redis::BaseError => e
          {
            status: :error,
            error_message: "Could not connect to Redis: #{e.message}"
          }
        rescue StandardError => e
          {
            status: :error,
            error_message: "Could not determine the status of job #{job_id}: #{e.message}"
          }
        ensure
          redis&.close
        end
      end

      def check_sidekiq_status(job_id)
        # Check various Sidekiq queues and sets for the job
        return :pending if Sidekiq::Queue.new.find_job(job_id)
        return :pending if Sidekiq::RetrySet.new.find_job(job_id)
        return :pending if Sidekiq::ScheduledSet.new.find_job(job_id)
        return :failed if Sidekiq::DeadSet.new.find_job(job_id)

        :completed_or_disappeared
      end
    end
  end
end
