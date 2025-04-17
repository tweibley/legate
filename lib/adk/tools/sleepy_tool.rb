# File: lib/adk/tools/sleepy_tool.rb
# frozen_string_literal: true

require_relative 'base_async_job_tool'

module ADK
  module Tools
    # An example ADK tool that starts a background job that sleeps for a specified duration.
    # This tool demonstrates how to implement a BaseAsyncJobTool with a Sidekiq worker.
    class SleepyTool < BaseAsyncJobTool
      define_metadata(
        name: :start_sleepy_job,
        description: 'Starts a background job that sleeps for a specified duration and then returns a message.',
        parameters: {
          duration: {
            type: :integer,
            description: 'How many seconds the job should sleep.',
            required: true
          },
          message: {
            type: :string,
            description: 'A message to include in the final result.',
            required: true
          }
        }
      )

      # Return the Sidekiq worker class to enqueue.
      def sidekiq_worker_class
        SleepyWorker
      end

      # Prepare the arguments for the worker's perform method.
      # Arguments must be JSON-serializable.
      def prepare_job_arguments(params, _context)
        duration = params[:duration].to_i
        message = params[:message].to_s
        [duration, message] # Must match SleepyWorker#perform signature
      end
    end

    # The Sidekiq worker that performs the actual sleep operation.
    class SleepyWorker
      include Sidekiq::Worker
      sidekiq_options queue: 'default', retry: 1

      # @param duration [Integer] How long to sleep in seconds.
      # @param message [String] The message to return upon completion.
      def perform(duration, message)
        jid = self.jid # Get the Job ID

        # --- Store initial pending status --- #
        begin
          ADK::Tools::BaseAsyncJobTool.store_job_pending(jid)
        rescue => e
          # Log error but try to continue if possible
          ADK.logger.error("[SleepyWorker JID: #{jid}] Failed to store initial pending status: #{e.message}")
        end
        # --- End store initial pending status --- #

        ADK.logger.info("[SleepyWorker JID: #{jid}] Starting job. Sleeping for #{duration} seconds...")

        begin
          sleep duration.to_i
          result_message = "Slept for #{duration} seconds. Your message: #{message}"
          ADK.logger.info("[SleepyWorker JID: #{jid}] Job finished. Storing result.")
          # Store the successful result using the helper from BaseAsyncJobTool
          ADK::Tools::BaseAsyncJobTool.store_job_result(jid, result_message)
        rescue => e
          error_message = "Job failed after starting sleep: #{e.message}"
          ADK.logger.error("[SleepyWorker JID: #{jid}] Job failed! Storing error. Error: #{error_message}")
          # Store the error using the helper
          ADK::Tools::BaseAsyncJobTool.store_job_error(jid, error_message, e.class.name)
        end
      end
    end
  end
end
