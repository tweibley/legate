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

tasks.each do |task|
  puts "\nExecuting task: '#{task}'"

  begin
    result_event = agent.run_task(
      session_id: session_id,
      user_input: task,
      session_service: session_service
    )

    # --- Result Handling ---
    puts "\nResult:"
    if result_event.is_a?(ADK::Event)
      puts " Status: Event Received"
      puts " Role: #{result_event.role}"

      content = result_event.content
      if content.is_a?(Array)
        puts " Content Type: Multi-Step Plan Results"
        content.each_with_index do |step_hash, index|
          print "  Step #{index + 1}: "
          if step_hash.is_a?(Hash) && step_hash[:status] == :success
            puts "Success | Result: #{step_hash[:result]}"
          elsif step_hash.is_a?(Hash) && step_hash[:status] == :error
            puts "Error   | Message: #{step_hash[:error_message]}"
          else
            puts "Unknown Format | Data: #{step_hash.inspect}"
          end
        end
      elsif content.is_a?(Hash) && content.key?(:status)
        if content[:status] == :success
          puts " Content Type: Single Step Success"
          puts " Result: #{content[:result]}"
        else
          puts " Content Type: Error"
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
  rescue => e
    puts "\nError executing task: #{e.class} - #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
end

# 6. --- Stop Agents ---
agent.stop
puts "\nAgents stopped:"
puts " - #{agent.name}: Running: #{agent.running?}"

puts "\n--- Example Complete ---"
