#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'legate'
require 'legate/planner'

# Set up the session service
Legate.config.session_service = Legate::SessionService::InMemory.new

# We'll create a simple MockPlanner that will be used to simulate LLM planning
# This planner will explicitly recognize delegation targets and route appropriately
class MockPlanner
  attr_reader :agent, :logger

  def initialize(agent:, **_options)
    @agent = agent
    @logger = Legate.logger
  end

  def plan(user_input)
    if !@agent.definition.respond_to?(:delegation_targets) || @agent.definition.delegation_targets.empty?
      # No delegation targets, just echo
      return {
        thought_process: "This agent doesn't have delegation targets, so I'll just echo the input.",
        steps: [{ tool: :echo, params: { message: "Direct response: #{user_input}" } }]
      }
    end

    # Check if we should delegate to calculator
    if @agent.definition.delegation_targets.include?(:calculator_agent) &&
       (user_input =~ %r{\d\s*[+\-*/]\s*\d} || user_input.downcase.include?('calculate') || user_input.downcase.include?('math'))

      {
        thought_process: 'This appears to be a math question, delegating to calculator_agent',
        steps: [
          {
            tool: :agent_transfer_to_calculator_agent,
            params: { task: user_input }
          }
        ]
      }
    # Check if we should delegate to researcher
    elsif @agent.definition.delegation_targets.include?(:researcher_agent) &&
          (user_input =~ /what\s+is|where\s+is|when\s+is|who\s+is|how\s+is|why\s+is|capital|country/)

      {
        thought_process: 'This appears to be a research question, delegating to researcher_agent',
        steps: [
          {
            tool: :agent_transfer_to_researcher_agent,
            params: { task: user_input }
          }
        ]
      }
    # Default to echoing
    else
      {
        thought_process: "I don't see a need to delegate this, so I'll just echo it back.",
        steps: [{ tool: :echo, params: { message: "Direct response: #{user_input}" } }]
      }
    end
  end
end

# Register the echo tool
class EchoTool < Legate::Tool
  def self.tool_metadata
    {
      name: :echo,
      description: 'Echo a message back to the user',
      parameters: {
        message: {
          type: 'string',
          description: 'The message to echo back',
          required: true
        }
      }
    }
  end

  def call(params)
    message = params[:message] || 'No message provided'
    { result: message }
  end
end

Legate::GlobalToolManager.register_tool(EchoTool)

# Define calculator tool
class CalculatorTool < Legate::Tool
  def self.tool_metadata
    {
      name: :calculator,
      description: 'Performs mathematical calculations',
      parameters: {
        expression: {
          type: 'string',
          description: 'Mathematical expression to evaluate',
          required: true
        }
      }
    }
  end

  def call(params)
    result = eval(params[:expression].gsub(%r{[^0-9+\-*/().]}, ''))
    { result: result }
  rescue StandardError => e
    { error: "Calculation error: #{e.message}" }
  end
end

Legate::GlobalToolManager.register_tool(CalculatorTool)

# Define the agent definitions
calculator_agent = Legate::AgentDefinition.new.define do |a|
  a.name :calculator_agent
  a.description 'An agent specialized in mathematical calculations'
  a.instruction 'You are a mathematical assistant. Solve math problems using the calculator tool.'
  a.use_tool :calculator
  a.use_tool :echo
end

researcher_agent = Legate::AgentDefinition.new.define do |a|
  a.name :researcher_agent
  a.description 'An agent specialized in answering research questions'
  a.instruction 'You are a research assistant. Answer questions based on your knowledge.'
  a.use_tool :echo
end

coordinator_agent = Legate::AgentDefinition.new.define do |a|
  a.name :coordinator_agent
  a.description 'An agent that coordinates tasks by delegating to specialized agents'
  a.instruction <<~INSTRUCTION
    You are a coordinator agent that delegates tasks to specialized agents.

    You have access to these specialized agents:
    1. calculator_agent - For mathematical calculations
    2. researcher_agent - For answering general knowledge questions

    Analyze each user request and delegate to the appropriate specialist agent.
  INSTRUCTION
  a.use_tool :echo
  a.can_delegate_to :calculator_agent, :researcher_agent
end

# Register all agent definitions globally
Legate::GlobalDefinitionRegistry.register(calculator_agent)
Legate::GlobalDefinitionRegistry.register(researcher_agent)
Legate::GlobalDefinitionRegistry.register(coordinator_agent)

# Create a session for this interaction
session_service = Legate.config.session_service
session = session_service.create_session(
  app_name: coordinator_agent.name,
  user_id: 'delegation_example_user'
)
session_id = session.id

# Create and initialize the calculator agent
calculator = Legate::Agent.new(definition: calculator_agent)
calculator_planner = MockPlanner.new(agent: calculator)
def calculator.planner
  @planner
end
calculator.instance_variable_set(:@planner, calculator_planner)

# Create and initialize the researcher agent
researcher = Legate::Agent.new(definition: researcher_agent)
researcher_planner = MockPlanner.new(agent: researcher)
def researcher.planner
  @planner
end
researcher.instance_variable_set(:@planner, researcher_planner)

# Create and initialize the coordinator agent
coordinator = Legate::Agent.new(definition: coordinator_agent)
coordinator_planner = MockPlanner.new(agent: coordinator)
def coordinator.planner
  @planner
end
coordinator.instance_variable_set(:@planner, coordinator_planner)

# Set up the parent-child relationships for agent hierarchy
calculator.instance_variable_set(:@parent_agent, coordinator)
researcher.instance_variable_set(:@parent_agent, coordinator)
coordinator.instance_variable_set(:@sub_agents, [calculator, researcher])

# Ensure all agents have their public_execute_step method for delegation
# This is done by the custom_agent_patch but let's make sure it's available

# Monkey patch the agent class to expose execute_step publicly (for testing only)
unless Legate::Agent.instance_methods.include?(:public_execute_step)
  Legate::Agent.class_eval do
    # Override execute_step to be public for testing
    def public_execute_step(step, session, session_service)
      # Handle special agent_transfer tool directly
      if step[:tool].to_s.start_with?('agent_transfer_to_')
        target_agent_name = step[:tool].to_s.sub('agent_transfer_to_', '').to_sym
        task = step[:params][:task]

        # Validate task parameter
        unless task
          return {
            status: :error,
            error_class: 'DelegationError',
            error_message: "Missing 'task' parameter for delegation to '#{target_agent_name}'"
          }
        end

        # Call transfer_to with the extracted target and task
        return transfer_to(target_agent_name, task, session.id, session_service)
      end

      # For non-agent-transfer steps, use the standard execute_step
      send(:execute_step, step, session, session_service)
    end
  end
end

# Start all agents
coordinator.start
calculator.start
researcher.start

puts '=' * 80
puts 'Multi-Agent Delegation Example (Using Proper Delegation)'
puts '=' * 80
puts 'Available commands:'
puts "- Type math questions like: 'What is 125 * 45?' to use the Calculator agent"
puts "- Type research questions like: 'What is the capital of France?' to use the Researcher agent"
puts "- Type 'exit' to quit"
puts '=' * 80

# Main interaction loop
loop do
  print "\nYour request > "
  user_input = gets.chomp

  break if user_input.downcase == 'exit'

  puts "\nProcessing request..."

  # Execute the coordinator agent with the user's input
  result_event = coordinator.run_task(
    session_id: session_id,
    user_input: user_input,
    session_service: session_service
  )

  # Parse and display the result
  content = result_event.content

  puts "\nResult:"
  puts '-' * 50

  if content[:error]
    puts "Error: #{content[:error]}"
  elsif content[:error_message]
    puts "Error: #{content[:error_message]}"
  elsif content[:target_agent] # For delegation results
    puts "Delegated to: #{content[:target_agent]}"
    puts "Response: #{content[:result][:result]}"
  else
    puts "Response: #{content[:result]}"
  end

  puts '-' * 50
end

# Clean up
coordinator.stop
calculator.stop
researcher.stop
puts "\nThank you for using the Multi-Agent Delegation Example!"
