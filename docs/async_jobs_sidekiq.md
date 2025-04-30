# Handling Asynchronous Jobs with Sidekiq

ADK provides support for initiating asynchronous background jobs using [Sidekiq](https://sidekiq.org/) and Redis. This allows tools to start potentially long-running tasks (like complex calculations, external API calls with long response times, or batch processing) without blocking the main agent execution flow.

The pattern involves two key components:

1.  **An ADK Tool to Start the Job:** A custom tool inheriting from `ADK::Tools::BaseAsyncJobTool` that enqueues a job in Sidekiq and immediately returns a `:pending` status with a unique `job_id`.
2.  **The `check_job_status` Tool:** A built-in ADK tool that uses the `job_id` to check the job's status in Sidekiq and retrieve the final result (or error) from Redis once the job is complete.

## Prerequisites

1.  **Sidekiq Gem:** Ensure `gem 'sidekiq'` is added to your project's `Gemfile` and installed via `bundle install`.
2.  **Running Redis Server:** Sidekiq requires a running Redis instance. Configure the Redis connection URL via the `REDIS_URL` environment variable or `ADK.configure { |c| c.redis_url = "..." }`. ADK will automatically configure the Sidekiq client to use this Redis instance.
3.  **Running Sidekiq Worker Process:** You **must** run a separate Sidekiq worker process in your application environment to actually process the jobs enqueued by your ADK tools. ADK only enqueues the jobs; it doesn't run the workers.

    Use the ADK CLI to manage Sidekiq workers:
    ```bash
    # Start a Sidekiq worker (uses ADK environment by default)
    adk sidekiq start

    # Start with custom options
    adk sidekiq start --queue default,critical --concurrency 10 --verbose

    # Check worker status
    adk sidekiq status

    # List pending jobs
    adk sidekiq list_jobs

    # Stop workers gracefully
    adk sidekiq stop
    ```

    For custom worker configurations, you can specify a require path:
    ```bash
    adk sidekiq start --require path/to/your/worker.rb
    ```

## 1. Implementing the Sidekiq Worker

This is the standard Sidekiq worker that contains your actual background task logic.

```ruby
# app/workers/my_long_task_worker.rb
require 'sidekiq'
require 'adk/tools/base_async_job_tool' # Needed for result storage helpers

class MyLongTaskWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'adk_jobs', retry: 5 # Example options

  # Arguments received here must be simple JSON-serializable types
  def perform(task_input, context_hash)
    jid = self.jid # Get the Job ID

    # --- Store initial pending status --- #
    begin
      ADK::Tools::BaseAsyncJobTool.store_job_pending(jid)
    rescue => e
      # Log error but try to continue if possible
      ADK.logger.error("[MyLongTaskWorker JID: #{jid}] Failed to store initial pending status: #{e.message}")
    end
    # --- End store initial pending status --- #

    ADK.logger.info("[MyLongTaskWorker JID: #{jid}] Starting job with input: #{task_input}")

    begin
      # --- Simulate long-running work ---
      sleep(10) # Example delay
      result = "Successfully processed '#{task_input}' using context #{context_hash}"
      # ----------------------------------

      # Store the successful result in Redis using the helper
      ADK::Tools::BaseAsyncJobTool.store_job_result(jid, result)
      ADK.logger.info("[MyLongTaskWorker JID: #{jid}] Job completed successfully.")

    rescue => e
      # Store the error details in Redis using the helper
      error_message = "Job failed after starting: #{e.message}"
      ADK.logger.error("[MyLongTaskWorker JID: #{jid}] #{error_message}")
      ADK::Tools::BaseAsyncJobTool.store_job_error(jid, error_message, e.class.name)
      # Optional: re-raise if you want Sidekiq's retry mechanism to handle it based on configuration
      # raise e
    end
  end
end
```

**Key Points:**

*   Include `Sidekiq::Worker`.
*   The `perform` method receives the arguments prepared by your ADK tool. **Arguments must be JSON-serializable.**
*   Use `self.jid` to get the unique Job ID.
*   Call `ADK::Tools::BaseAsyncJobTool.store_job_pending(jid)` at the start to indicate the job has begun processing.
*   On success, call `ADK::Tools::BaseAsyncJobTool.store_job_result(jid, your_result)`.
*   On failure, call `ADK::Tools::BaseAsyncJobTool.store_job_error(jid, error_message, error_class_name)`.

## 2. Implementing the ADK Tool (`BaseAsyncJobTool`)

This tool acts as the trigger from the ADK agent's perspective.

```ruby
# lib/adk/tools/my_long_task_tool.rb
require_relative '../tool'
require_relative 'base_async_job_tool'
# Assuming your worker class is autoloaded or required elsewhere
# require_relative '../../app/workers/my_long_task_worker' # Or adjust path

module ADK
  module Tools
    class MyLongTaskTool < BaseAsyncJobTool
      define_metadata(
        name: :start_long_task,
        description: 'Initiates a long-running background task with the provided input.',
        parameters: {
          task_data: { type: :string, required: true, description: 'Input data for the task' }
        }
      )

      # Return the Sidekiq worker class to use
      def sidekiq_worker_class
        MyLongTaskWorker # The class defined above
      end

      # Optional: Customize job options like queue or retry count
      # def sidekiq_job_options
      #   super.merge({ 'queue' => 'adk_critical', 'retry' => 1 })
      # end

      # Prepare arguments for the worker's `perform` method
      # Must return an array of JSON-serializable arguments.
      def prepare_job_arguments(params, context)
        [
          params[:task_data], # First arg for MyLongTaskWorker#perform
          context.to_h        # Second arg for MyLongTaskWorker#perform
        ]
      end
    end
  end
end
```

**Key Points:**

*   Inherit from `ADK::Tools::BaseAsyncJobTool`.
*   Implement `sidekiq_worker_class` to return your worker class.
*   Implement `prepare_job_arguments` to return an array of simple arguments for the worker's `perform` method.
*   The base class handles enqueuing the job and returning `{ status: :pending, job_id: <jid> }`.

## 3. Using the Tools in an Agent

To use this pattern, the agent needs both the tool that starts the job (`MyLongTaskTool` in this example) and the built-in `check_job_status` tool.

```ruby
require 'adk'
# Assuming tool and worker classes are loaded

# Agent Setup
# Assuming MyLongTaskTool is defined in ./tools/my_long_task_tool.rb
agent = ADK::Agent.new(
  name: 'job_runner_agent',
  description: 'Runs and checks background jobs',
  # Automatically load MyLongTaskTool from ./tools
  # The built-in check_job_status tool is usually available automatically
  tool_paths: './tools'
)

# Manual addition no longer needed if tools are discovered:
# agent.add_tool(ADK::Tools::MyLongTaskTool.new)
# # check_job_status is often added automatically if Sidekiq is configured,
# # but adding it explicitly doesn't hurt.
# agent.add_tool(ADK::ToolRegistry.create_instance(:check_job_status))

# Session Setup
session_service = ADK::SessionService::Redis.new # Use Redis for session and job results
session = session_service.create_session(app_name: agent.name, user_id: 'job_user')

# --- Interaction Flow ---

# 1. User asks to start the long task
user_input_start = "Start the long task with input 'important data'"
start_event = agent.run_task(session_id: session.id, user_input: user_input_start, session_service: session_service)

# start_event.content will be something like:
# { status: :pending, job_id: "jid_xyz123", message: "Job enqueued." }
job_id = start_event.content[:job_id]
puts "Task started, Job ID: #{job_id}"

# 2. Add a small initial delay before polling to give the worker time to start processing
sleep 0.5

# 3. Poll for job completion
max_attempts = 30
attempt = 0
start_time = Time.now

while attempt < max_attempts
  attempt += 1
  
  # Check job status
  check_event = agent.run_task(
    session_id: session.id,
    user_input: "Check the status of job #{job_id}",
    session_service: session_service
  )

  if check_event.content.is_a?(Hash)
    status = check_event.content[:status]&.to_sym

    case status
    when :success
      elapsed = Time.now - start_time
      puts "\nJob completed successfully! (took #{elapsed.round(1)} seconds)"
      puts "Result: #{check_event.content[:result]}"
      break
    when :error
      elapsed = Time.now - start_time
      puts "\nJob failed! (after #{elapsed.round(1)} seconds)"
      puts "Error: #{check_event.content[:error_message]}"
      break
    when :pending
      print "." # Progress indicator
      $stdout.flush
    else
      elapsed = Time.now - start_time
      puts "\nUnexpected job status '#{status}' received after #{elapsed.round(1)}s"
      puts "Raw status content: #{check_event.content.inspect}"
      break
    end
  end

  sleep 1 # Wait before next poll
end

if attempt >= max_attempts
  elapsed = Time.now - start_time
  puts "\nPolling timed out after #{max_attempts} attempts (#{elapsed.round(1)} seconds)"
end
```

**Key Points for Polling:**

1. Add a small initial delay (0.5 seconds) before starting to poll to give the worker time to start processing and store its initial pending status.
2. Use a maximum number of attempts to prevent infinite polling.
3. Show progress with dots (`.`) for pending status.
4. Handle all possible status responses (`:success`, `:error`, `:pending`).
5. Include elapsed time in status messages for better user feedback.

## How `check_job_status` Works

1.  **Checks Redis:** It first looks for a key like `adk:job_result:<job_id>` in Redis. If found, it parses the JSON data stored there (which should be a hash containing `:status` and either `:result` or `:error_message`) and returns that directly. This is the primary way to get results/errors from completed jobs.
2.  **Checks Sidekiq API:** If no result is found in Redis, it queries the Sidekiq API (`Sidekiq::Queue`, `Sidekiq::RetrySet`, `Sidekiq::DeadSet`, etc.) to see if the job is currently queued, running, scheduled for retry, or in the dead set.
    *   If found in queues/retries/scheduled -> Returns `:pending`.
    *   If found in dead set -> Returns `:error` (indicating failure after retries).
    *   If not found anywhere *and* no result in Redis -> Returns `:error` (job likely completed long ago and Redis key expired, or it vanished unexpectedly).

This ensures that the tool provides the final outcome if available via Redis, otherwise gives the current Sidekiq processing state.

## Example: SleepyTool

ADK includes a complete example of an async job tool in `examples/sleep_agent.rb`. This example demonstrates:

1. A simple worker that sleeps for a specified duration
2. A tool that starts the sleep job
3. Proper polling with progress indicators
4. Error handling and timeout management

Run the example with:
```bash
ADK_LOG_LEVEL=DEBUG ruby examples/sleep_agent.rb
```

This will show the complete flow of:
1. Starting a background job
2. Polling for its status
3. Retrieving the final result 