#!/usr/bin/env ruby
# frozen_string_literal: true

# If running from project root: bundle exec ruby examples/random_calculator.rb
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

# 4. --- Session Setup ---
# Create a session service and session
session_service = ADK::SessionService::InMemory.new
session = session_service.create_session(app_name: agent.name, user_id: 'example_user')
session_id = session.id
puts "\nCreated session: #{session_id}"

# 5. --- Task Execution ---
task = "Get a random number between 10 and 20, then multiply it by 3."
puts "\nRunning high-level task via agent.run_task: '#{task}'"

# Set log level to DEBUG to see planner details if needed
# ENV['ADK_LOG_LEVEL'] = 'DEBUG'
# ADK.instance_variable_set(:@logger, nil) # Force logger re-init

begin
  result_event = agent.run_task(
    session_id: session_id,
    user_input: task,
    session_service: session_service
  )
  puts "Raw result event: #{result_event.inspect}" # Show the structure

  # --- Updated Result Handling ---
  puts "\nInterpreted Result:"
  if result_event.is_a?(ADK::Event)
    puts " Status: Event Received"
    puts " Role: #{result_event.role}"

    content = result_event.content
    if content.is_a?(Array)
      puts " Content Type: Multi-Step Plan Results"
      any_errors = false
      content.each_with_index do |step_hash, index|
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
    elsif content.is_a?(Hash) && content.key?(:status)
      # Single step plan or a planning error
      if content[:status] == :success
        puts " Content Type: Single Step Success"
        puts " Result: #{content[:result]}"
      else # status == :error or other
        puts " Content Type: Error (or Single Step Error)"
        puts " Message: #{content[:error_message]}"
      end
    else
      puts " Content Type: String or Other Format"
      puts " Content: #{content}"
    end
  else
    puts " Status: Unknown (Unexpected Format)"
    puts " Raw Data: #{result_event.inspect}"
  end
  # --- End Updated Result Handling ---
rescue => e
  puts "Error executing task: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# 6. --- Stop Agent ---
agent.stop
puts "\nAgent '#{agent.name}' stopped. Running: #{agent.running?}"
puts "\n--- Example Complete ---"
