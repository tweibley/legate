#!/usr/bin/env ruby
# frozen_string_literal: true

# If running from project root: bundle exec ruby examples/01_simple_agent.rb
require_relative '../lib/legate'

# Load .env and map GEMINI_API_KEY -> GOOGLE_API_KEY (as the `legate` CLI does).
# The library never reads .env on its own; an application must opt in.
Legate.load_environment

puts '--- Simple Echo Agent Example (Session-Based) ---'

# 1. --- Agent Definition Setup ---
simple_echo_definition = Legate::AgentDefinition.new.define do |a|
  a.name :simple_echo_agent # Agent name as a Symbol
  a.description 'A simple agent that can echo messages'
  a.instruction 'You are an echo agent. Your task is to repeat the user\'s input exactly.' # Instruction is required
  a.use_tool :echo # Tool name as a Symbol, Legate::Tools::Echo should be globally discoverable
end

# Optional: Register with GlobalDefinitionRegistry if this definition needs to be found by name later
# Legate::GlobalDefinitionRegistry.register(simple_echo_definition)

# Ensure the tool is globally available (Legate::Tools::Echo should be by default)
# If Legate::Tools::Echo wasn't automatically registered, you might need:
# Legate::GlobalToolManager.register_tool(Legate::Tools::Echo)

# 2. --- Agent Instantiation ---
# Initialize the agent with the definition object
agent = Legate::Agent.new(definition: simple_echo_definition)

puts "\nAgent '#{agent.name}' created with tool: #{agent.tools.first&.name || 'none'}"

# 3. --- Start Agent ---
agent.start
puts "Agent started. Running: #{agent.running?}"

# 4. --- Session Setup ---
session_service = Legate::SessionService::InMemory.new
session = session_service.create_session(app_name: agent.name, user_id: 'example_user')
session_id = session.id
puts "\nCreated session: #{session_id}"

# 5. --- Task Execution ---
task = 'Hello, world!'
puts "\nExecuting task: '#{task}'"

begin
  result_event = agent.run_task(
    session_id: session_id,
    user_input: task,
    session_service: session_service
  )
  puts "Raw result event: #{result_event.inspect}"

  # --- Updated Result Handling ---
  puts "\nInterpreted Result:"
  if result_event.is_a?(Legate::Event)
    puts ' Status: Event Received'
    puts " Role: #{result_event.role}"

    content = result_event.content
    if content.is_a?(Array)
      puts ' Content Type: Multi-Step Plan Results'
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
        puts ' Content Type: Single Step Success'
        puts " Result: #{content[:result]}"
      else # status == :error or other
        puts ' Content Type: Error (or Single Step Error)'
        puts " Message: #{content[:error_message]}"
      end
    else
      puts ' Content Type: String or Other Format'
      puts " Content: #{content}"
    end
  else
    puts ' Status: Unknown (Unexpected Format)'
    puts " Raw Data: #{result_event.inspect}"
  end
  # --- End Updated Result Handling ---
rescue StandardError => e
  puts "\nError executing task: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# 6. --- Stop Agent ---
agent.stop
puts "\nAgent stopped. Running: #{agent.running?}"
puts "\n--- Example Complete ---"
