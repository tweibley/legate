#!/usr/bin/env ruby
# frozen_string_literal: true

# If running from project root: bundle exec ruby examples/00_quickstart.rb
require_relative '../lib/legate'

# Load .env and map GEMINI_API_KEY -> GOOGLE_API_KEY (as the `legate` CLI does).
# The library never reads .env on its own; an application must opt in.
Legate.load_environment

puts '--- Quickstart: agent.ask in one line ---'

# Define an agent. Only `name` is required — `instruction` is optional (it
# defaults from the name/description), and `use_tool` selects a tool (here a
# built-in; you can also pass a Legate::Tool subclass to register + select it).
agent = Legate::Agent.new(definition: Legate::AgentDefinition.new.define do |a|
  a.name :quickstart_agent
  a.description 'Repeats what the user says.'
  a.use_tool :echo
end)

# `ask` is the convenience path: it starts the agent, creates a session, runs
# the task, and returns the final event. No start/create_session/stop dance.
event = agent.ask('Echo this back: Hello, Legate!')

# Read the result off the event — no reaching into event.content.
puts "Answer:  #{event.answer}"
puts "Success: #{event.success?}"
puts "Error:   #{event.error_message}" if event.error?

puts "\n--- Watch progress live (optional block) ---"
# Pass a block to stream each lifecycle event as it happens (user message, each
# tool request/result, final answer) — handy for a CLI spinner or a UI.
agent.ask('Repeat: streaming works') do |e|
  puts "  #{e.role}#{e.tool_name ? " (#{e.tool_name})" : ''}"
end

# `ask` makes a fresh session each call. To keep context across turns, create a
# session once and pass its id to each ask:
#
#   session = agent.session_service.create_session(app_name: agent.name.to_s, user_id: 'demo')
#   agent.ask('first question',  session_id: session.id)
#   agent.ask('a follow-up',     session_id: session.id)
#
# See examples 02+ for multi-tool planning, custom tools, sessions, and more.

# `ask` does not auto-stop (it stays warm for more questions). Stop a long-lived
# agent when you're done to release any MCP connections.
agent.stop

puts "\n--- Quickstart Complete ---"
