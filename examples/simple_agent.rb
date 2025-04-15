#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/adk'
require_relative '../lib/adk/tools/echo'

# Create a new agent
agent = ADK::Agent.new(
  name: 'simple_agent',
  description: 'A simple agent that can echo messages'
)

# Add the echo tool to the agent
agent.add_tool(ADK::Tools::Echo.new)

# Start the agent
agent.start

# Execute a task
result = agent.run_task('Hello, world!')
puts "Result: #{result}"

# Stop the agent
agent.stop 