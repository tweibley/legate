#!/usr/bin/env ruby
# frozen_string_literal: true

# If running from project root: ruby examples/multi_tool_agent.rb
require_relative '../lib/adk'

puts "--- Multi-Tool Agent Example ---"

# 1. --- Agent Setup ---
agent = ADK::Agent.new(
  name: 'multi_tool_agent',
  description: 'An agent that can use multiple tools including echo, calculator, cat facts, random numbers, and task delegation'
)

# 2. --- Add Tools ---
# Add all available tools
tools = [
  ADK::ToolRegistry.create_instance(:echo),
  ADK::ToolRegistry.create_instance(:calculator),
  ADK::ToolRegistry.create_instance(:cat_facts),
  ADK::ToolRegistry.create_instance(:random_number),
  ADK::ToolRegistry.create_instance(:delegate_task)
]

tools.each do |tool|
  unless tool
    puts "Error: Tool not found in registry."
    exit 1
  end
  agent.add_tool(tool)
end

puts "\nAgent '#{agent.name}' created with tools:"
agent.tools.each { |tool| puts " - #{tool.name}" }

# 3. --- Start Agent ---
agent.start
puts "\nAgent started. Running: #{agent.running?}"

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
  "Generate a random number between 1 and 10"
]

# Add the delegate task only if Redis is available and set up calculator agent
begin
  redis = Redis.new
  redis.ping

  # Set up calculator agent definition in Redis
  calculator_agent_key = "adk:agent:calculator_agent"
  calculator_agent_def = {
    'description' => 'A calculator agent that can perform basic arithmetic operations',
    'tools' => '["calculator"]',
    'model' => 'gemini-2.0-flash'
  }
  redis.hmset(
    calculator_agent_key,
    'description', calculator_agent_def['description'],
    'tools', calculator_agent_def['tools'],
    'model', calculator_agent_def['model']
  )

  tasks << "Delegate this task to calculator_agent: what is 20 / 4"
  puts "\nRedis connection successful and calculator agent configured. Added delegation task."
rescue Redis::CannotConnectError => e
  puts "\nRedis connection failed: #{e.message}"
  puts "Skipping delegation task as it requires Redis."
end

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

# 6. --- Stop Agent ---
agent.stop
puts "\nAgent stopped. Running: #{agent.running?}"
puts "\n--- Example Complete ---" 