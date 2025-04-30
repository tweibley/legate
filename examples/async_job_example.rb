# File: examples/async_job_example.rb
# frozen_string_literal: true

puts "To see this work end-to-end:"
puts "1. Ensure Redis is running."
puts "2. Start a Sidekiq worker: bundle exec adk sidekiq start"
puts "3. Run this script: bundle exec ruby examples/async_job_example.rb"

# This example demonstrates how to use an ADK tool that starts
# an asynchronous Sidekiq background job and how to check its status.

# --- Setup ---
# Load ADK and necessary components
require_relative '../lib/adk'

# Load the custom tool class
require_relative 'tools/sleepy_tool'
# Note: The worker itself (sleepy_worker.rb) needs to be loaded by the Sidekiq process,
# not necessarily by this script, unless you are using Sidekiq inline testing.

puts "--- Async Job Example ---"

# Configure ADK (ensure REDIS_URL in .env points to your Redis)
# ADK.configure do |config|
#   config.redis_url = ENV['REDIS_URL'] || 'redis://localhost:6379/1'
# end

# --- Agent Setup ---
puts "\nSetting up agent..."
agent = ADK::Agent.new(
  name: 'async_job_runner',
  description: 'An agent that can start and check background jobs.',
  # Add SleepyTool and CheckJobStatusTool classes
  tool_classes: [ADK::Tools::SleepyTool, ADK::Tools::CheckJobStatusTool]
)

# The check_job_status tool is now added via tool_classes
puts "Agent Tools: #{agent.tools.map(&:name)}"

# --- Session Setup ---
# Use in-memory session for this example
session_service = ADK::SessionService::InMemory.new
session = session_service.create_session(app_name: agent.name, user_id: 'async_example_user')
puts "Created session: #{session.id}"

# --- Task Execution ---

# Start the agent runtime
agent.start

# 1. Start the sleepy job
task_input_start = "Start a sleepy job that waits 5 seconds with message 'Hello Async!'"
puts "\nRunning task: '#{task_input_start}'"

# Simulate planner choosing the sleepy_tool
# In a real scenario, the planner would generate this plan:
plan_start = [
  { tool: :start_sleepy_job, params: { duration: 5, message: 'Hello Async!' } }
]

# Execute the plan step manually for demonstration
# (Alternatively, use agent.run_task and provide prompt engineering for the LLM to generate the plan)
puts "Executing plan step: #{plan_start.first.inspect}"

# Need the session object for execute_step
current_session = session_service.get_session(session_id: session.id)

start_result_hash = agent.send(:execute_step, plan_start.first, current_session, session_service)

puts "\nResult from starting the job:"
puts JSON.pretty_generate(start_result_hash)

unless start_result_hash[:status] == :pending && start_result_hash[:job_id]
  puts "\nError: Expected pending status with job_id! Aborting."
  agent.stop
  exit 1
end

job_id = start_result_hash[:job_id]
puts "\nJob enqueued with ID: #{job_id}"
puts "(Note: A Sidekiq worker process must be running and loading 'examples/workers/sleepy_worker.rb' to actually execute this job)"

# 2. Check the job status (immediately - likely still pending)
task_input_check = "Check status for job #{job_id}"
puts "\nRunning task: '#{task_input_check}'"

plan_check = [
  { tool: :check_job_status, params: { job_id: job_id } }
]

puts "Executing plan step: #{plan_check.first.inspect}"
check_result_hash_1 = agent.send(:execute_step, plan_check.first, current_session, session_service)

puts "\nResult from first status check:"
puts JSON.pretty_generate(check_result_hash_1)

# 3. Wait and check again
wait_time = 7 # Wait longer than the job's sleep duration
puts "\nWaiting #{wait_time} seconds for the job to likely complete..."
sleep wait_time

puts "\nRunning task: '#{task_input_check}' (again)"
puts "Executing plan step: #{plan_check.first.inspect}"
check_result_hash_2 = agent.send(:execute_step, plan_check.first, current_session, session_service)

puts "\nResult from second status check:"
puts JSON.pretty_generate(check_result_hash_2)

# Stop the agent runtime
agent.stop

puts "\n--- Example Finished ---"
