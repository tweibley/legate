#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'adk'
require 'adk/custom_agent_patch'

# Define a MockPlanner class that handles delegation
class MockPlanner
  attr_reader :agent, :logger, :model_name
  
  def initialize(agent:, model_name: nil, **options)
    @agent = agent
    @logger = options[:logger] || ADK.logger
    @model_name = model_name || 'mock-model'
  end
  
  def plan(user_input)
    input_lower = user_input.downcase
    
    if input_lower.match?(/[\d\s\+\-\*\/\(\)]+/) || input_lower.match?(/calculate|math|sum|multiply|divide|subtract|add/)
      # Math question - delegate to calculator
      if @agent.definition.delegation_targets&.include?(:calculator_agent)
        return create_delegation_plan(:calculator_agent, user_input)
      end
    elsif input_lower.match?(/who|what|where|when|why|how|explain|describe|tell me|history|science|geography|capital|country/)
      # Knowledge question - delegate to researcher
      if @agent.definition.delegation_targets&.include?(:researcher_agent)
        return create_delegation_plan(:researcher_agent, user_input)
      end
    end
    
    # Default: just echo back
    create_echo_plan("Default response: #{user_input}")
  end
  
  private
  
  def create_delegation_plan(target_agent, task)
    {
      thought_process: "This task should be delegated to the #{target_agent}",
      steps: [
        {
          tool: :"agent_transfer_to_#{target_agent}",
          params: { task: task }
        }
      ]
    }
  end
  
  def create_echo_plan(message)
    {
      thought_process: "I'll just echo a response",
      steps: [
        {
          tool: :echo,
          params: { message: message }
        }
      ]
    }
  end
end

# Set up the session service
ADK.config.session_service = ADK::SessionService::InMemory.new
#ADK.config.definition_store = ADK::DefinitionStore::InMemory.new

# Register a simple echo tool
class EchoTool < ADK::Tool
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

# Define a calculator tool
class CalculatorTool < ADK::Tool
  def self.tool_metadata
    {
      name: :calculator,
      description: 'Performs mathematical calculations',
      parameters: {
        expression: {
          type: 'string',
          description: 'The mathematical expression to evaluate',
          required: true
        }
      }
    }
  end

  def call(params)
    begin
      # Note: Using eval is unsafe in production, this is just for demonstration
      result = eval(params[:expression])
      { result: result }
    rescue => e
      { error: "Calculation error: #{e.message}" }
    end
  end
end

# Register the tools
ADK::GlobalToolManager.register_tool(EchoTool)
ADK::GlobalToolManager.register_tool(CalculatorTool)

# Define a Calculator Agent
calculator_agent = ADK::AgentDefinition.new.define do |a|
  a.name :calculator_agent
  a.description 'An agent specialized in mathematical calculations'
  a.instruction 'You are a mathematical assistant. Solve math problems using the calculator tool.'
  a.use_tool :calculator
  a.use_tool :echo
  a.output_key :calculation_result
end

# Define a Research Agent
researcher_agent = ADK::AgentDefinition.new.define do |a|
  a.name :researcher_agent
  a.description 'An agent specialized in answering research questions'
  a.instruction 'You are a research assistant. Answer factual questions based on your knowledge.'
  a.use_tool :echo
  a.output_key :research_result
end

# Define the Coordinator Agent
coordinator_agent = ADK::AgentDefinition.new.define do |a|
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

# Register all agent definitions
ADK::GlobalDefinitionRegistry.register(calculator_agent)
ADK::GlobalDefinitionRegistry.register(researcher_agent)
ADK::GlobalDefinitionRegistry.register(coordinator_agent)

# Create a single session for the interaction
session_service = ADK.config.session_service
session = session_service.create_session(app_name: coordinator_agent.name, user_id: 'delegation_example_user')
session_id = session.id

# Create the agent instances
coordinator = ADK::Agent.new(definition: coordinator_agent)
calculator = ADK::Agent.new(definition: calculator_agent)
researcher = ADK::Agent.new(definition: researcher_agent)

# Set up the mock planner for the coordinator
mock_planner = MockPlanner.new(agent: coordinator)

# Override the planner method for the coordinator
def coordinator.planner
  @planner
end

# Set the mock planner on the coordinator
coordinator.instance_variable_set(:@planner, mock_planner)

# Override calculator agent's run_task method to handle calculations directly
def calculator.run_task(session_id:, user_input:, session_service:, **options)
  # Extract numbers from the input
  numbers = user_input.scan(/-?\d+/)
  result = nil
  
  if user_input =~ /\d+\s*\*\s*\d+/ # Multiplication
    result = numbers[0].to_i * numbers[1].to_i
  elsif user_input =~ /\d+\s*\+\s*\d+/ # Addition
    result = numbers[0].to_i + numbers[1].to_i
  elsif user_input =~ /\d+\s*-\s*\d+/ # Subtraction
    result = numbers[0].to_i - numbers[1].to_i
  elsif user_input =~ /\d+\s*\/\s*\d+/ # Division
    result = numbers[0].to_f / numbers[1].to_f
  else
    # Try to evaluate the expression
    begin
      result = eval(user_input.gsub(/[^0-9+\-*\/\(\)\.]/,''))
    rescue
      result = "Unable to calculate: #{user_input}"
    end
  end
  
  ADK::Event.new(
    role: :agent,
    content: { result: "The result is: #{result}" }
  )
end

# Override researcher agent's run_task method for simplicity
def researcher.run_task(session_id:, user_input:, session_service:, **options)
  topic = user_input.gsub(/what is|where is|who is|tell me about/i, '').strip
  
  ADK::Event.new(
    role: :agent,
    content: { result: "Research result for: #{topic}" }
  )
end

# Establish parent-child relationships
calculator.instance_variable_set(:@parent_agent, coordinator)
researcher.instance_variable_set(:@parent_agent, coordinator)
coordinator.instance_variable_set(:@sub_agents, [calculator, researcher])

# Enable delegation in the coordinator agent's planner
require 'adk/planner'

# Force the coordinator to recreate its planner with delegation capabilities
planner = ADK::Planner.new(agent: coordinator)
coordinator.instance_variable_set(:@planner, planner)

# Start all agents
coordinator.start
calculator.start
researcher.start

puts "=" * 80
puts "Multi-Agent Delegation Example"
puts "=" * 80
puts "Available commands:"
puts "- Type math questions like: 'What is 125 * 45?' to use the Calculator agent"
puts "- Type research questions like: 'What is the capital of France?' to use the Researcher agent"
puts "- Type 'exit' to quit"
puts "=" * 80

# Main interaction loop
loop do
  print "\nYour request > "
  user_input = gets.chomp
  
  break if user_input.downcase == 'exit'
  
  puts "\nProcessing request..."
  
  # Execute the coordinator agent with the user's input
  result_event = coordinator.run_task(
    session_id: session_id, # Use the persistent session ID
    user_input: user_input,
    session_service: ADK.config.session_service
  )
  
  # Parse and display the result
  content = result_event.content
  
  puts "\nResult:"
  puts "-" * 50
  
  if content[:error]
    puts "Error: #{content[:error]}"
  elsif content[:error_message]
    puts "Error: #{content[:error_message]}"
  elsif content[:target_agent] # For delegation results
    puts "Delegated to: #{content[:target_agent]}"
    if content[:result] && content[:result][:result]
      puts "Response: #{content[:result][:result]}"
    else
      puts "Response: #{content[:result]}"
    end
  else
    puts "Response: #{content[:result]}"
  end
  
  puts "-" * 50
end

# Clean up
coordinator.stop
calculator.stop
researcher.stop
puts "\nThank you for using the Multi-Agent Delegation Example!" 