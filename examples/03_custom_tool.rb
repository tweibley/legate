#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Creating a Custom Tool
#
# This example shows how to build a custom tool from scratch using the
# Legate::Tool DSL: define parameters, implement perform_execution,
# and wire it into an agent.
#
# Run with: bundle exec ruby examples/03_custom_tool.rb

require_relative '../lib/legate'

# Load .env and map GEMINI_API_KEY -> GOOGLE_API_KEY (as the `legate` CLI does).
# The library never reads .env on its own; an application must opt in.
Legate.load_environment

puts '--- Custom Tool Example ---'

# 1. Define a custom tool by inheriting from Legate::Tool
class GreetingTool < Legate::Tool
  tool_description 'Generates a personalized greeting message.'

  parameter :name, type: :string, required: true,
                   description: 'The name of the person to greet'

  parameter :style, type: :string, required: false,
                    description: 'Greeting style: formal, casual, or pirate (default: casual)'

  private

  def perform_execution(params, _context)
    name = params[:name]
    style = (params[:style] || 'casual').downcase

    greeting = case style
               when 'formal'
                 "Good day, #{name}. It is a pleasure to make your acquaintance."
               when 'pirate'
                 "Ahoy, #{name}! Welcome aboard, ye scurvy dog!"
               else
                 "Hey #{name}, nice to meet you!"
               end

    { status: :success, result: greeting }
  rescue StandardError => e
    { status: :error, error_message: "Greeting failed: #{e.message}" }
  end
end

# 2. Register the tool globally so agents can find it by name
Legate::GlobalToolManager.register_tool(GreetingTool)
puts "Registered tool: #{GreetingTool.tool_name}"

# 3. Use the tool directly (without an agent)
puts "\n--- Direct Tool Usage ---"
tool = GreetingTool.new
context = Legate::ToolContext.new(
  session_id: 'demo-session',
  user_id: 'demo-user',
  app_name: 'custom_tool_example'
)

%w[casual formal pirate].each do |style|
  result = tool.execute({ name: 'Alice', style: style }, context)
  puts "  #{style}: #{result[:result]}"
end

# 4. Wire the tool into an agent
puts "\n--- Agent with Custom Tool ---"
agent_definition = Legate::AgentDefinition.new.define do |a|
  a.name :greeter_agent
  a.description 'An agent that greets people in different styles'
  a.instruction 'You are a greeting specialist. Use the greeting tool to greet people. Choose the style that best fits the request.'
  a.use_tool :greeting_tool
end

agent = Legate::Agent.new(definition: agent_definition)
agent.start

session_service = Legate::SessionService::InMemory.new
session = session_service.create_session(app_name: agent.name, user_id: 'example_user')

result = agent.run_task(
  session_id: session.id,
  user_input: 'Greet Captain Blackbeard in pirate style',
  session_service: session_service
)

puts "Agent result: #{result.content.inspect}"

agent.stop
puts "\n--- Example Complete ---"
