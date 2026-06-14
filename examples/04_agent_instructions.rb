#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Agent Instructions (System Prompts)
#
# Demonstrates defining an agent with specific instructions (system prompt)
# that guide its behavior during planning.
#
# Run with: bundle exec ruby examples/04_agent_instructions.rb

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'legate'

# Load .env and map GEMINI_API_KEY -> GOOGLE_API_KEY (as the `legate` CLI does).
# The library never reads .env on its own; an application must opt in.
Legate.load_environment
require 'legate/tools/echo'       # Ensure tool classes are loaded for GlobalToolManager
require 'legate/tools/calculator' # to find them by name.

# 1. Define the Agent with Instructions
# =====================================

# Create the AgentDefinition object first
concise_calculator_definition = Legate::AgentDefinition.new.define do |a|
  a.name :concise_calculator # Use symbol for name
  a.description 'A calculator agent that tries to be concise.'
  # Provide instructions to the planner
  a.instruction 'You are a calculator assistant. When asked to calculate, use the calculator tool. Respond only with the final numerical result, no extra words.'
  # Add necessary tools by name
  a.use_tool :calculator
  a.use_tool :echo # Echo might be used by fallback or if planner chooses it
end

# Instantiate the Agent using the definition
agent = Legate::Agent.new(definition: concise_calculator_definition)

# 2. Setup Session Service
# ========================
session_service = Legate::SessionService::InMemory.new
session = session_service.create_session(app_name: agent.name, user_id: 'instruct_user')

# 3. Start Agent and Run Task
# ==========================
begin
  puts "Starting agent '#{agent.name}'..."
  agent.start

  task = 'What is 5 plus 12?'
  puts "\nRunning task: '#{task}'"

  # The planner will receive the instruction along with the task and tool list.
  # The LLM should ideally follow the instruction to generate a plan
  # that results in a concise response (though the final response formatting
  # also depends on the tool's output and agent logic).
  result_event = agent.run_task(
    session_id: session.id,
    user_input: task,
    session_service: session_service
  )

  puts "\n--- Agent Response ---"
  puts "  Role: #{result_event.role}"
  puts "  Content: #{result_event.content.inspect}"

  # Example of a task the instructions might prevent (if LLM obeys)
  task_inappropriate = 'Tell me a long story about the number 7.'
  puts "\nRunning task: '#{task_inappropriate}' (Agent instructed to only calculate)"
  result_event_2 = agent.run_task(
    session_id: session.id,
    user_input: task_inappropriate,
    session_service: session_service
  )
  puts "\n--- Agent Response (Second Task) ---"
  puts "  Role: #{result_event_2.role}"
  puts "  Content: #{result_event_2.content.inspect}"
  # Expected: Agent might respond with planning failure because the task doesn't match its instructions.
ensure
  puts "\nStopping agent '#{agent.name}'..."
  agent.stop
  puts 'Agent stopped.'
end

puts "\nExample finished."
