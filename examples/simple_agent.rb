#!/usr/bin/env ruby
# frozen_string_literal: true

# If running from project root: ruby examples/simple_agent.rb
require_relative '../lib/adk'

# Create a new agent
agent = ADK::Agent.new(
  name: 'simple_echo_agent',
  description: 'A simple agent that can echo messages'
)

# Add the echo tool (it should auto-register, just need to add instance to agent)
echo_tool = ADK::ToolRegistry.create_instance(:echo)
unless echo_tool
  puts "Error: Echo tool not found in registry."
  exit 1
end
agent.add_tool(echo_tool)
puts "Agent '#{agent.name}' created with tool: #{agent.tools.first.name}"

# Start the agent
agent.start
puts "Agent started."

# Execute a task
task = 'Hello, world!'
puts "Executing task: '#{task}'"
result_data = agent.run_task(task)
puts "Raw result data: #{result_data.inspect}" # Show the hash

# --- Updated Result Handling ---
puts "\nInterpreted Result:"
if result_data.is_a?(Hash) && result_data.key?(:status)
  if result_data[:status] == :success
    puts " Status: Success"
    puts " Result: #{result_data[:result]}"
  else # status == :error or other
    puts " Status: Error"
    puts " Error: #{result_data[:error_message]}"
  end
else
  # Handle unexpected format (shouldn't happen with current agent logic, but good practice)
  puts " Status: Unknown (Unexpected Format)"
  puts " Raw Data: #{result_data.inspect}"
end
# --- End Updated Result Handling ---

# Stop the agent
agent.stop
puts "\nAgent stopped."
