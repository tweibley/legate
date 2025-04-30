#!/usr/bin/env ruby
# frozen_string_literal: true

# If running from project root: bundle exec ruby examples/multi_tool_agent.rb
require_relative '../lib/adk'

puts "--- Multi-Tool Agent Example ---"

# 1. --- Agent Setup ---
# Add required tool classes directly during initialization
agent = ADK::Agent.new(
  name: 'multi_tool_agent',
  description: 'An agent that can use multiple tools including echo, calculator, cat facts, random numbers, and task delegation',
  tool_classes: [
    ADK::Tools::Echo,
    ADK::Tools::Calculator,
    ADK::Tools::CatFacts,
    ADK::Tools::RandomNumberTool,
    ADK::Tools::AgentTool # Note: AgentTool provides :delegate_task
  ]
)

# Create definition for the calculator agent that will be used for delegation
calculator_agent_def = {
  name: :calculator_agent,
  description: 'A calculator agent that can perform basic arithmetic operations',
  model: 'gemini-2.0-flash',
  tools: ['calculator'] # Tool names as strings
}

# --- Register Calculator Agent Definition In-Memory for this run --- >
# This makes it findable by the AgentTool without needing Redis persistence for the example.
# In a real application, definitions would typically be saved/loaded via CLI or other means.
if ADK::AgentDefinitionStore.register(calculator_agent_def[:name], calculator_agent_def)
  puts "\nRegistered definition for '#{calculator_agent_def[:name]}' in memory for this execution."
else
  puts "\nFailed to register definition for '#{calculator_agent_def[:name]}'."
  exit 1
end
# <--------------------------------------------------------------------------

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
  "Echo this message: Hello from multi-tool agent!",
  "Calculate 15 * 7",
  "Get me a cat fact",
  "Generate a random number between 1 and 10",
  "Delegate this task to calculator_agent: what is 20 / 4"
]

# Array to store results for summary table
task_results = []

tasks.each_with_index do |task, index|
  task_num = index + 1
  puts "\n" + "=" * 40
  puts "--- Task #{task_num}: '#{task}' ---"
  puts "=" * 40

  outcome_message = "[Execution Error]"
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
  puts "=" * 40 # End separator for this task's logs
end

# 6. --- Print Summary Table --- #
puts "\n" + "#" * 50
puts "### Task Execution Summary ###"
puts "#" * 50
# Determine column width (simple approach)
max_task_len = task_results.map { |r| r[:task].length }.max || 40
puts "
| #{'Task'.ljust(max_task_len)} | Outcome                         |"
puts "|#{'-' * (max_task_len + 2)}|---------------------------------|"
task_results.each do |r|
  puts "| #{r[:task].ljust(max_task_len)} | #{r[:outcome]} "
end
puts ""

# 7. --- Stop Agent --- #
agent.stop
puts "\nAgents stopped:"
puts " - #{agent.name}: Running: #{agent.running?}"

puts "\n--- Example Complete ---"
