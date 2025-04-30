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
      # --- New DSL Metadata ---
      # Name :check_job_status_tool will be inferred
      self.explicit_tool_name = :check_job_status # Keep original name

      tool_description 'Checks the status and retrieves the result of a previously started background job (Sidekiq) using its ID.'

      parameter :job_id,
                type: :string,
                description: 'The ID of the job to check status for',
                required: true
      # --- End New DSL Metadata ---

      private

      # @param params [Hash] Must contain :job_id.
      # @param _context [ADK::ToolContext, nil] The execution context (unused here).
      # @return [Hash] { status: :pending/:success/:error, ... }
      def perform_execution(params, _context)
        job_id = params[:job_id]

        unless job_id && !job_id.strip.empty?
          raise ADK::ToolArgumentError, 'Missing required parameter: job_id'
        end

        redis = nil # Define outside begin block for ensure
        begin
          redis = Redis.new(ADK.redis_options)
          result_key = "#{ADK::Tools::BaseAsyncJobTool::JOB_RESULT_REDIS_PREFIX}#{job_id}"

          # First check Redis for completed results
          stored_result = redis.get(result_key)
          if stored_result
            begin
              parsed_result = JSON.parse(stored_result, symbolize_names: true)
              if parsed_result.is_a?(Hash) && parsed_result[:status]
                parsed_result[:status] = parsed_result[:status].to_sym
                ADK.logger.info("CheckJobStatusTool: Found stored result for job #{job_id}")
                return parsed_result # Return the full stored hash (success or error)
              else
                err_msg = "Invalid data format found in Redis for job #{job_id}: #{stored_result}"
                ADK.logger.error(err_msg)
                raise ADK::ToolError, err_msg # Raise ToolError for invalid format
              end
            rescue StandardError => e
              err_msg = "Failed to process stored result for job #{job_id} (Error: #{e.class}): #{e.message}. Data: #{stored_result}"
              ADK.logger.error(err_msg)
              raise ADK::ToolError, err_msg # Raise ToolError for any processing failure
            end
          end

          # --- Execution ONLY continues here if stored_result was nil --- #

          # If no valid result in Redis, check Sidekiq status
          begin
            status = check_sidekiq_status(job_id)
            ADK.logger.info("CheckJobStatusTool: Sidekiq status for job #{job_id}: #{status}")
          rescue StandardError => e
            # Catch errors from check_sidekiq_status (e.g., mocked API errors)
            err_msg = "Could not determine the status of job #{job_id} via Sidekiq API: #{e.message}"
            ADK.logger.error("#{err_msg} (#{e.class})")
            raise ADK::ToolError, err_msg # Wrap in ToolError
          end

          case status
          when :pending
            {
              status: :pending,
              job_id: job_id,
              message: "Job is queued or currently running."
            }
          when :failed
            # Job failed and ended up in Dead Set
            raise ADK::ToolError, "Job has failed (found in Sidekiq Dead Set)."
          when :completed_or_disappeared
            # Job not found in Sidekiq or Redis
            raise ADK::ToolError,
                  "Job result is unavailable. The job may have completed without storing a result, or the job ID may be invalid."
          end
        rescue Redis::BaseError => e
          err_msg = "Could not connect to Redis to check job status: #{e.message}"
          ADK.logger.error(err_msg)
          raise ADK::ToolError, err_msg
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
