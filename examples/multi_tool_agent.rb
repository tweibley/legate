#!/usr/bin/env ruby
# frozen_string_literal: true

# If running from project root: bundle exec ruby examples/multi_tool_agent.rb
require_relative '../lib/adk'

puts '--- Multi-Tool Agent Example ---'

# 1. --- Agent Definitions ---

# Definition for the main multi-tool agent
multi_tool_agent_definition = ADK::AgentDefinition.new.define do |a|
  a.name :multi_tool_agent
  a.description 'An agent that can use multiple tools including echo, calculator, cat facts, random numbers, and task delegation'
  a.instruction 'You are a versatile assistant. Use the appropriate tool for the user\'s request. For calculations, use the calculator. For cat facts, use cat_facts. For random numbers, use random_number. To delegate, use delegate_task.'
  a.use_tool :echo
  a.use_tool :calculator
  a.use_tool :cat_facts      # Assumes a CatFactsTool providing :cat_facts is available
  a.use_tool :random_number  # Assumes a RandomNumberTool providing :random_number is available
  a.use_tool :delegate_task  # Provided by ADK::Tools::AgentTool
end

# Definition for the calculator agent that will be used for delegation
calculator_agent_definition = ADK::AgentDefinition.new.define do |a|
  a.name :calculator_agent
  a.description 'A calculator agent that can perform basic arithmetic operations'
  a.instruction 'You are a calculator. Perform the requested calculation.'
  a.model_name 'gemini-2.0-flash' # Optional: specify model for this agent
  a.use_tool :calculator
end

# --- Register Calculator Agent Definition for AgentTool --- >
# AgentTool will look up definitions in the GlobalDefinitionRegistry.
ADK::GlobalDefinitionRegistry.register(calculator_agent_definition)
puts "\nRegistered definition for '#{calculator_agent_definition.name}' in ADK::GlobalDefinitionRegistry."
# <----------------------------------------------------------

# Ensure all necessary tools are globally available/registered.
# Standard tools like Echo, Calculator, AgentTool (delegate_task) are usually auto-registered.
# For custom tools like CatFactsTool and RandomNumberTool, ensure they are loaded and registered
# e.g., via `require` and `ADK::GlobalToolManager.register_tool(CatFactsTool)` if not already.
# This example assumes they are available to the GlobalToolManager.

# 2. --- Agent Instantiation ---
agent = ADK::Agent.new(definition: multi_tool_agent_definition)

puts "\nAgent '#{agent.name}' created with tools:"
agent.tools.each { |tool| puts " - #{tool.name}" }

# 3. --- Start Agent ---
agent.start
puts "\nAgent started:"
puts " - #{agent.name}: Running: #{agent.running?}"

# 4. --- Session Setup ---
session_service = ADK::SessionService::InMemory.new
session = session_service.create_session(app_name: agent.name, user_id: 'example_user')
session_id = session.id
puts "\nCreated session: #{session_id}"

# 5. --- Task Execution Examples ---
tasks = [
  'Echo this message: Hello from multi-tool agent!',
  'Calculate 15 * 7',
  'Get me a cat fact',
  'Generate a random number between 1 and 10',
  'Delegate this task to calculator_agent: what is 20 / 4'
]

# Array to store results for summary table
task_results = []

tasks.each_with_index do |task, index|
  task_num = index + 1
  puts "\n" + '=' * 40
  puts "--- Task #{task_num}: '#{task}' ---"
  puts '=' * 40

  outcome_message = '[Execution Error]'
  begin
    result_event = agent.run_task(
      session_id: session_id,
      user_input: task,
      session_service: session_service
    )

    # --- Extract final outcome for summary --- #
    if result_event.is_a?(ADK::Event) && result_event.content.is_a?(Hash)
      content = result_event.content
      if content[:status] == :success
        final_result = content[:result]
        # Handle nested result from delegation
        if final_result.is_a?(Hash) && final_result.key?(:status) && final_result[:status] == :success
          outcome_message = "Success: #{final_result[:result]}"
        else
          outcome_message = "Success: #{final_result}"
        end
      elsif content[:status] == :error
        outcome_message = "Error: #{content[:error_message]}"
      else # Pending or other statuses
        outcome_message = "Status: #{content[:status]}"
        outcome_message += " (#{content[:message]})" if content[:message]
      end
    else
      outcome_message = "[Unexpected Result Format]: #{result_event.inspect}"
    end
  rescue => e
    outcome_message = "[Execution Error]: #{e.message}"
    puts "\nError executing Task #{task_num}: #{e.class} - #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
  # Store the result
  task_results << { task: task, outcome: outcome_message }
  puts '=' * 40 # End separator for this task's logs
end

# 6. --- Print Summary Table --- #
puts "\n" + '#' * 50
puts '### Task Execution Summary ###'
puts '#' * 50
# Determine column width (simple approach)
max_task_len = task_results.map { |r| r[:task].length }.max || 40
puts "
| #{'Task'.ljust(max_task_len)} | Outcome                         |"
puts "|#{'-' * (max_task_len + 2)}|---------------------------------|"
task_results.each do |r|
  puts "| #{r[:task].ljust(max_task_len)} | #{r[:outcome]} "
end
puts ''

# 7. --- Stop Agent --- #
agent.stop
puts "\nAgents stopped:"
puts " - #{agent.name}: Running: #{agent.running?}"

puts "\n--- Example Complete ---"
