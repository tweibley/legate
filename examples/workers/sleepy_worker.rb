# File: examples/workers/sleepy_worker.rb
# frozen_string_literal: true

# --- Example: Sidekiq Worker for Async ADK Tools ---
#
# This script sets up a Sidekiq worker to process async jobs
# from ADK tools like SleepyTool. It demonstrates how to:
# 1. Configure Sidekiq with Redis
# 2. Define a worker class that processes ADK tool jobs
# 3. Handle job status updates via Redis
#
# Prerequisites:
#   - Redis must be running
#   - Run this with: bundle exec sidekiq -r ./examples/workers/sleepy_worker.rb
#
# -------------------------------------------------------------

$LOAD_PATH.unshift File.expand_path('../../../lib', __FILE__) # Adjust path for nested dir
require 'adk'
ADK.load_environment # Handle Bundler, Dotenv, etc.

require 'sidekiq'
require 'adk/tools/sleepy_tool'

# Configure Sidekiq to use Redis
Sidekiq.configure_server do |config|
  config.redis = { url: 'redis://localhost:6379/0' }
end

Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://localhost:6379/0' }
end

# Define the worker class that will process SleepyTool jobs
class SleepyToolWorker
  include Sidekiq::Worker

  def perform(job_id, duration)
    ADK.logger.info("Processing SleepyTool job #{job_id} with duration #{duration}s")

    # Update job status to running
    ADK::Tools::CheckJobStatusTool.update_job_status(job_id, :running)

    # Create and execute the tool
    tool = ADK::Tools::SleepyTool.new
    result = tool.perform(duration: duration)

    # Update job status with result
    if result.success?
      ADK::Tools::CheckJobStatusTool.update_job_status(job_id, :success, result.value)
    else
      ADK::Tools::CheckJobStatusTool.update_job_status(job_id, :error, result.error)
    end

    ADK.logger.info("Completed SleepyTool job #{job_id}")
  rescue StandardError => e
    ADK.logger.error("Failed to process SleepyTool job #{job_id}: #{e.message}")
    ADK::Tools::CheckJobStatusTool.update_job_status(job_id, :error, e.message)
  end
end

# Log that the worker is ready
ADK.logger.info('SleepyTool worker loaded and ready to process jobs')
