#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Session State Management
#
# This example demonstrates how Legate manages state:
# - Creating sessions with initial state
# - Reading and writing state via the session service
# - How tools produce state deltas that agents apply
# - Inspecting event history after task execution
#
# Run with: bundle exec ruby examples/05_state_and_sessions.rb

require_relative '../lib/legate'

# Load .env and map GEMINI_API_KEY -> GOOGLE_API_KEY (as the `legate` CLI does).
# The library never reads .env on its own; an application must opt in.
Legate.load_environment

puts '--- State & Sessions Example ---'

# 1. Create a session service and session with initial state
session_service = Legate::SessionService::InMemory.new
session = session_service.create_session(
  app_name: 'state_example',
  user_id: 'demo_user',
  initial_state: { visits: 0, greeting: 'Welcome!' }
)
session_id = session.id

puts "Created session: #{session_id}"
puts 'Initial state:'
session.state.each_pair { |k, v| puts "  #{k}: #{v.inspect}" }

# 2. Direct state manipulation via session service
puts "\n--- Session Service State Operations ---"
session_service.set_state(session_id: session_id, key: :visits, value: 1)
session_service.set_state(session_id: session_id, key: :preference, value: 'dark_mode')

visits = session_service.get_state(session_id: session_id, key: :visits)
pref = session_service.get_state(session_id: session_id, key: :preference)
puts "  visits: #{visits}"
puts "  preference: #{pref}"

# 3. How tools interact with state
puts "\n--- Tool State Pattern ---"
puts '  Tools use context.state_get/state_set to read/write state.'
puts "  state_set accumulates a 'pending delta' that the agent applies"
puts '  to the session after the tool completes. This ensures state'
puts '  changes are tracked alongside events.'

# 4. Create an agent and run a task to see events and state in action
puts "\n--- Agent Task with Events ---"
agent_definition = Legate::AgentDefinition.new.define do |a|
  a.name :state_demo_agent
  a.description 'Demonstrates state in agent context'
  a.instruction 'You are a helpful agent. Echo back what the user says.'
  a.use_tool :echo
end

agent = Legate::Agent.new(definition: agent_definition)
agent.start

result = agent.run_task(
  session_id: session_id,
  user_input: 'Remember that I visited the examples page',
  session_service: session_service
)

puts "  Task result: #{result.content.inspect}"

# 5. Inspect event history
puts "\n--- Event History ---"
final_session = session_service.get_session(session_id: session_id)
puts "  Total events: #{final_session.events.size}"
final_session.events.each_with_index do |event, i|
  role = event.role
  content_preview = case event.content
                    when String then event.content[0..60]
                    when Hash then event.content[:status] || event.content.keys.first
                    else event.content.class
                    end
  puts "  #{i + 1}. [#{role}] #{content_preview}"
end

# 6. Final state
puts "\n--- Final State ---"
final_session.state.each_pair { |k, v| puts "  #{k}: #{v.inspect}" }

agent.stop
puts "\n--- Example Complete ---"
