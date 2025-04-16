#!/usr/bin/env ruby
# frozen_string_literal: true

# If running from project root: ruby examples/random_calculator.rb
require_relative '../lib/adk'

puts "--- Random Calculator Agent Example (Multi-Step Planner w/ Hash Results) ---"

# 1. --- Agent Setup ---
agent = ADK::Agent.new(
  name: 'multi_step_hash_agent_001',
  description: 'An agent that uses multiple tools and returns structured results.'
)

# 2. --- Add Tools ---
random_tool = ADK::ToolRegistry.create_instance(:random_number)
calculator_tool = ADK::ToolRegistry.create_instance(:calculator)

unless random_tool && calculator_tool
  puts "Error: Could not find :random_number or :calculator tool."
  exit 1
end

agent.add_tool(random_tool)
agent.add_tool(calculator_tool)

puts "\nAgent '#{agent.name}' created."
puts "Agent tools loaded: #{agent.tools.map(&:name).join(', ')}"

# 3. --- Start Agent ---
agent.start
puts "\nAgent '#{agent.name}' started. Running: #{agent.running?}"

# 4. --- Task Execution ---
task = "Get a random number between 10 and 20, then multiply it by 3."
puts "\nRunning high-level task via agent.run_task: '#{task}'"

# Set log level to DEBUG to see planner details if needed
# ENV['ADK_LOG_LEVEL'] = 'DEBUG'
# ADK.instance_variable_set(:@logger, nil) # Force logger re-init

result_data = agent.run_task(task)
puts "Raw result data: #{result_data.inspect}" # Show the structure

# --- Updated Result Handling ---
puts "\nInterpreted Result:"
if result_data.is_a?(Array)
  puts " Status: Multi-Step Plan Executed"
  any_errors = false
  result_data.each_with_index do |step_hash, index|
    print "  Step #{index + 1}: "
    if step_hash.is_a?(Hash) && step_hash[:status] == :success
      puts "Success | Result: #{step_hash[:result]}"
    elsif step_hash.is_a?(Hash) && step_hash[:status] == :error
      puts "Error   | Message: #{step_hash[:error_message]}"
      any_errors = true
    else
      puts "Unknown Format | Data: #{step_hash.inspect}"
      any_errors = true # Treat unexpected format as problematic
    end
  end
  puts " Overall Plan Status: #{any_errors ? 'Completed with errors' : 'Completed successfully'}"

elsif result_data.is_a?(Hash) && result_data.key?(:status)
  # Single step plan or a planning error
  if result_data[:status] == :success
    puts " Status: Single Step Success"
    puts " Result: #{result_data[:result]}"
  else # status == :error or other
    puts " Status: Error (or Single Step Error)"
    puts " Message: #{result_data[:error_message]}"
  end
else
  puts " Status: Unknown (Unexpected Format)"
  puts " Raw Data: #{result_data.inspect}"
end
# --- End Updated Result Handling ---

# 5. --- Stop Agent ---
agent.stop
puts "\nAgent '#{agent.name}' stopped. Running: #{agent.running?}"
puts "\n--- Example Complete ---"
