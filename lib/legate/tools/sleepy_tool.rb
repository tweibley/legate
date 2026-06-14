# File: lib/legate/tools/sleepy_tool.rb
# frozen_string_literal: true

require_relative 'base_async_job_tool'

module Legate
  module Tools
    # An example Legate tool that starts a background job that sleeps for a specified duration.
    # This tool demonstrates how to implement a BaseAsyncJobTool with a background worker.
    class SleepyTool < BaseAsyncJobTool
      # --- New DSL Metadata ---
      # Name will be inferred as :sleepy_tool
      self.explicit_tool_name = :start_sleepy_job # Keep original name

      tool_description 'Starts a background job that sleeps for a specified duration and then returns a message.'

      parameter :duration,
                type: :integer,
                description: 'How many seconds the job should sleep.',
                required: true

      parameter :message,
                type: :string,
                description: 'A message to include in the final result.',
                required: true
      # --- End New DSL Metadata ---

      # Return the worker class to use.
      def worker_class
        SleepyWorker
      end

      # Prepare the arguments for the worker's perform method.
      # Arguments must be JSON-serializable.
      def prepare_job_arguments(params, _context)
        duration = params[:duration].to_i
        message = params[:message].to_s
        [duration, message] # Must match SleepyWorker#perform signature (after jid)
      end
    end

    # The worker that performs the actual sleep operation.
    class SleepyWorker
      # @param jid [String] The Job ID (passed as first argument by BaseAsyncJobTool).
      # @param duration [Integer] How long to sleep in seconds.
      # @param message [String] The message to return upon completion.
      def perform(jid, duration, message)
        # --- Store initial pending status --- #
        begin
          Legate::Tools::BaseAsyncJobTool.store_job_pending(jid)
        rescue StandardError => e
          # Log error but try to continue if possible
          Legate.logger.error("[SleepyWorker JID: #{jid}] Failed to store initial pending status: #{e.message}")
        end
        # --- End store initial pending status --- #

        Legate.logger.info("[SleepyWorker JID: #{jid}] Starting job. Sleeping for #{duration} seconds...")

        begin
          sleep duration.to_i
          result_message = "Slept for #{duration} seconds. Your message: #{message}"
          Legate.logger.info("[SleepyWorker JID: #{jid}] Job finished. Storing result.")
          # Store the successful result using the helper from BaseAsyncJobTool
          Legate::Tools::BaseAsyncJobTool.store_job_result(jid, result_message)
        rescue StandardError => e
          error_message = "Job failed after starting sleep: #{e.message}"
          Legate.logger.error("[SleepyWorker JID: #{jid}] Job failed! Storing error. Error: #{error_message}")
          # Store the error using the helper
          Legate::Tools::BaseAsyncJobTool.store_job_error(jid, error_message, e.class.name)
        end
      end
    end
  end
end
