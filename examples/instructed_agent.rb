#!/usr/bin/env ruby
# frozen_string_literal: true

# File: examples/instructed_agent.rb

# Demonstrates defining an agent with specific instructions (system prompt)
# that guide its behavior during planning.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'adk'
require 'adk/tools/echo'       # Ensure tool classes are loaded for GlobalToolManager
require 'adk/tools/calculator' # to find them by name.

# 1. Define the Agent with Instructions
# =====================================

# Create the AgentDefinition object first
concise_calculator_definition = ADK::AgentDefinition.new.define do |a|
  a.name :concise_calculator # Use symbol for name
  a.description 'A calculator agent that tries to be concise.'
  # Provide instructions to the planner
  a.instruction 'You are a calculator assistant. When asked to calculate, use the calculator tool. Respond only with the final numerical result, no extra words.'
  # Add necessary tools by name
  a.use_tool :calculator
  a.use_tool :echo # Echo might be used by fallback or if planner chooses it
end

# Instantiate the Agent using the definition
agent = ADK::Agent.new(definition: concise_calculator_definition)

# 2. Setup Session Service
# ========================
session_service = ADK::SessionService::InMemory.new
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

  puts "\n--- Agent Response Event ---"
  puts result_event.inspect

  # Display the processed response content
  puts "\n--- Formatted Agent Response ---"
  response_processor = ADK::Web::App.new # Use helper from Web App for consistency
  processed = response_processor.send(:process_agent_response, result_event)
  puts processed[:display_content]

  # Example of a task the instructions might prevent (if LLM obeys)
  task_inappropriate = 'Tell me a long story about the number 7.'
  puts "\nRunning task: '#{task_inappropriate}' (Agent instructed to only calculate)"
  result_event_2 = agent.run_task(
    session_id: session.id,
    user_input: task_inappropriate,
    session_service: session_service
  )
  puts "\n--- Agent Response Event (Second Task) ---"
  puts result_event_2.inspect
  puts "\n--- Formatted Agent Response (Second Task) ---"
  processed_2 = response_processor.send(:process_agent_response, result_event_2)
  puts processed_2[:display_content]
  # Expected: Agent might respond with planning failure because the task doesn't match its instructions.

ensure
  puts "\nStopping agent '#{agent.name}'..."
  agent.stop
  puts 'Agent stopped.'
end

puts "\nExample finished." 