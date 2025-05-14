#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/adk'
# Require the specific tool class if not automatically loaded. SleepyTool provides :start_sleepy_job.
require_relative 'tools/sleepy_tool'
# ADK::Tools::CheckJobStatusTool (providing :check_job_status) is loaded by ADK core.

puts '--- Async Job Agent Example (Polling Status) ---'

# 1. --- Agent Definition ---
async_job_demo_definition = ADK::AgentDefinition.new.define do |a|
  a.name :async_job_demo_agent
  a.description 'An agent that starts a background job and can check its status.'
  a.instruction 'You can start sleepy jobs and check their status. Use start_sleepy_job to initiate, and the system might use check_job_status for monitoring.'
  a.use_tool :start_sleepy_job # Provided by ADK::Tools::SleepyTool
  a.use_tool :check_job_status # Provided by ADK::Tools::CheckJobStatusTool
end

# 2. --- Agent Instantiation ---
agent = ADK::Agent.new(definition: async_job_demo_definition)

# Get an instance of the status checker tool directly (needed for manual polling in this example script)
status_checker_tool = ADK::GlobalToolManager.create_instance(:check_job_status)
unless status_checker_tool
  puts 'Error: Status checker tool (:check_job_status) not found in GlobalToolManager.'
  exit 1
end

puts "\nAgent '#{agent.name}' created with tools: #{agent.tools.map(&:name).join(', ')}"
puts "Status checker tool for manual polling: #{status_checker_tool.name}"

# 3. --- Start Agent (Needed for the initial task) ---
agent.start
puts 'Agent started.'

# 4. --- Session Setup ---
# We use a session service to store the conversation history, including tool results.
session_service = ADK::SessionService::InMemory.new
session = session_service.create_session(app_name: agent.name, user_id: 'demo_user')
session_id = session.id
puts "\nCreated session: #{session_id}"

# 5. --- Task Execution & Polling ---
# The task asks the agent to use the async tool.
job_duration = rand(3..8) # Random duration for the job
task = "Start a sleepy job for #{job_duration} seconds with message 'Demo complete'"
puts "\nExecuting task: '#{task}'"

job_id = nil
final_job_status = nil

begin
  # --- Run the task that starts the job ---
  agent.run_task(
    session_id: session_id,
    user_input: task,
    session_service: session_service
  )

  # --- Check Session History for the Job ID ---
  puts "\nTask finished. Checking session history for the job ID..."
  current_session = session_service.get_session(session_id: session_id)
  # Find the result event from the tool that starts the job
  start_job_event = current_session&.events&.reverse&.find do |event|
    event.role == :tool_result && event.tool_name == :start_sleepy_job
  end

  # --- Polling for Job Completion ---
  if start_job_event&.content&.is_a?(Hash) && start_job_event.content[:status] == :pending
    job_id = start_job_event.content[:job_id]
    puts "Found pending job: #{job_id}. Starting polling using #{status_checker_tool.name}..."

    # Add a small initial delay to give the worker time to start processing
    sleep 0.5

    max_attempts = 30
    attempt = 0
    start_time = Time.now
    polling_context = ADK::ToolContext.new(session_id: session_id, app_name: 'polling_script', user_id: 'demo_user')

    while attempt < max_attempts
      attempt += 1

      # Execute the status checker tool directly
      status_result = status_checker_tool.execute({ job_id: job_id }, polling_context)

      if status_result.is_a?(Hash)
        final_job_status = status_result[:status]&.to_sym # Ensure symbol

        case final_job_status
        when :success
          elapsed = Time.now - start_time
          puts "\nJob completed successfully! (took #{elapsed.round(1)} seconds)"
          puts "Result: #{status_result[:result]}"
          break
        when :error
          elapsed = Time.now - start_time
          puts "\nJob failed! (after #{elapsed.round(1)} seconds)"
          puts "Error: #{status_result[:error_message]}"
          break
        when :pending
          print '.' # Progress indicator
          $stdout.flush
        else
          elapsed = Time.now - start_time
          puts "\nUnexpected job status '#{final_job_status}' received after #{elapsed.round(1)}s. Stopping poll."
          puts "Raw status content: #{status_result.inspect}"
          break
        end
      else
        elapsed = Time.now - start_time
        puts "\nUnexpected result format from status checker tool after #{elapsed.round(1)}s: #{status_result.inspect}. Stopping poll."
        final_job_status = :error # Treat unexpected format as an error
        break
      end

      sleep 1 # Wait before next poll
    end

    if attempt >= max_attempts && final_job_status == :pending
      elapsed = Time.now - start_time
      puts "\nPolling timed out after #{max_attempts} attempts (#{elapsed.round(1)} seconds). Job status still pending."
    end

  elsif start_job_event
    puts "Job start step did not return a pending status. Status: #{start_job_event.content[:status]}"
    final_job_status = start_job_event.content[:status]
  else
    puts "Could not find the result event for '#{sleepy_tool.name}' in the session history."
    final_job_status = :error # Indicate failure if job start wasn't found
  end
rescue => e
  puts "\nError during task execution or polling: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
  final_job_status = :error # Indicate failure on exception
end

# 6. --- Stop Agent ---
puts "\nStopping agent..."
agent.stop
puts 'Agent stopped.'

# 7. --- Final Summary ---
puts "\n--- Example Summary ---"
if job_id
  puts "Job ID: #{job_id}"
  puts "Final Status: #{final_job_status || 'Unknown'}"
else
  puts 'Job ID: Not found'
  puts "Final Status: #{final_job_status || 'Error'}"
end
puts '--- Example Complete ---'
