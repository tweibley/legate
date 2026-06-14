# File: examples/tools/sleepy_tool.rb
# frozen_string_literal: true

# Ensure the base tool is loadable
require_relative '../../lib/legate/tools/base_async_job_tool'

module Legate
  module Tools
    # An example Legate tool that starts a background job that sleeps.
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

      # Return the worker class to run in the background.
      def worker_class
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
  end
end
