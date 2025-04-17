# File: examples/workers/sleepy_worker.rb
# frozen_string_literal: true

require 'sidekiq'
# Assuming adk-ruby is loaded or required appropriately in your Sidekiq environment
# If running standalone sidekiq, you might need: require_relative '../../lib/adk'

# A simple worker that simulates a long-running task by sleeping.
class SleepyWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'default', retry: 1 # Example options

  # @param duration [Integer] How long to sleep in seconds.
  # @param message [String] The message to return upon completion.
  def perform(duration, message)
    jid = self.jid # Get the Job ID
    puts "[SleepyWorker JID: #{jid}] Starting job. Sleeping for #{duration} seconds..."

    begin
      sleep duration.to_i
      result_message = "Slept for #{duration} seconds. Your message: #{message}"
      puts "[SleepyWorker JID: #{jid}] Job finished. Storing result."
      # Store the successful result using the helper from BaseAsyncJobTool
      ADK::Tools::BaseAsyncJobTool.store_job_result(jid, result_message)
    rescue => e
      error_message = "Job failed after starting sleep: #{e.message}"
      puts "[SleepyWorker JID: #{jid}] Job failed! Storing error. Error: #{error_message}"
      # Store the error using the helper
      ADK::Tools::BaseAsyncJobTool.store_job_error(jid, error_message, e.class.name)
      # Optional: re-raise if you want Sidekiq's retry/deadset logic to trigger based on the exception
      # raise e
    end
  end
end
