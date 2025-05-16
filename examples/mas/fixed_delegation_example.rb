#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'adk'

# Set up the session service
ADK.config.session_service = ADK::SessionService::InMemory.new

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

# Register the echo tool
ADK::GlobalToolManager.register_tool(EchoTool)

# Define a Calculator Agent
calculator_agent = ADK::AgentDefinition.new.define do |a|
  a.name :calculator_agent
  a.description 'An agent specialized in mathematical calculations'
  a.instruction 'You are a mathematical assistant.'
  a.use_tool :echo
end

# Define a Research Agent
researcher_agent = ADK::AgentDefinition.new.define do |a|
  a.name :researcher_agent
  a.description 'An agent specialized in answering research questions'
  a.instruction 'You are a research assistant.'
  a.use_tool :echo
end

# Define the Coordinator Agent
coordinator_agent = ADK::AgentDefinition.new.define do |a|
  a.name :coordinator_agent
  a.description 'An agent that coordinates tasks by delegating to specialized agents'
  a.instruction 'You are a coordinator agent.'
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

# Custom delegation implementation
class CustomCoordinator < ADK::Agent
  def run_task(session_id:, user_input:, session_service:, **options)
    # First check for math expressions with a more precise regex
    if is_math_question?(user_input)
      # Mathematics question - route to calculator
      puts "Delegating to calculator agent..."
      calculator = find_agent(:calculator_agent)
      result = calculator.run_task(session_id: session_id, user_input: user_input, session_service: session_service)
      return ADK::Event.new(role: :agent, content: { result: "Calculator says: #{result.content[:result]}" })
    elsif is_research_question?(user_input)
      # Knowledge question - route to researcher
      puts "Delegating to researcher agent..."
      researcher = find_agent(:researcher_agent)
      result = researcher.run_task(session_id: session_id, user_input: user_input, session_service: session_service)
      return ADK::Event.new(role: :agent, content: { result: "Researcher says: #{result.content[:result]}" })
    else
      # Default handling - echo
      return ADK::Event.new(role: :agent, content: { result: "I'm not sure how to handle: #{user_input}" })
    end
  end
  
  private
  
  def is_math_question?(input)
    # Check for explicit math operators between numbers
    return true if input =~ /\d\s*[\+\-\*\/]\s*\d/
    
    # Check for explicit math keywords
    math_keywords = ["calculate", "math", "sum", "add", "subtract", "multiply", "divide"]
    math_keywords.any? { |keyword| input.downcase.include?(keyword) }
  end
  
  def is_research_question?(input)
    # Check for question words
    question_patterns = [
      /what\s+is/i, /where\s+is/i, /who\s+is/i, /why\s+is/i, /how\s+is/i, 
      /tell\s+me\s+about/i, /capital/i, /country/i, 
      /what\s+are/i, /where\s+are/i, /who\s+are/i
    ]
    
    question_patterns.any? { |pattern| input =~ pattern }
  end
end

# Create custom calculator with direct response
class CustomCalculator < ADK::Agent
  def run_task(session_id:, user_input:, session_service:, **options)
    # Simple calculation handling
    begin
      # Strip non-math characters and evaluate
      stripped_input = user_input.gsub(/[^0-9+\-*\/\(\)\.]/,'')
      result = eval(stripped_input)
      return ADK::Event.new(role: :agent, content: { result: "The result is: #{result}" })
    rescue
      # If we can't evaluate, just echo back
      return ADK::Event.new(role: :agent, content: { result: "I couldn't calculate: #{user_input}" })
    end
  end
end

# Create custom researcher with direct response
class CustomResearcher < ADK::Agent
  def run_task(session_id:, user_input:, session_service:, **options)
    # Extract the topic from questions like "what is X?"
    topic = user_input.gsub(/what is|where is|who is|tell me about/i, '').strip
    
    # For France questions specifically
    if topic.downcase.include?('france') && user_input.downcase.include?('capital')
      return ADK::Event.new(role: :agent, content: { result: "The capital of France is Paris." })
    end
    
    # Default research response
    return ADK::Event.new(role: :agent, content: { result: "Research information about: #{topic}" })
  end
end

# Create the custom agents instead of standard ones
custom_coordinator = CustomCoordinator.new(definition: coordinator_agent)
custom_calculator = CustomCalculator.new(definition: calculator_agent)
custom_researcher = CustomResearcher.new(definition: researcher_agent)

# Establish parent-child relationships
custom_calculator.instance_variable_set(:@parent_agent, custom_coordinator)
custom_researcher.instance_variable_set(:@parent_agent, custom_coordinator)
custom_coordinator.instance_variable_set(:@sub_agents, [custom_calculator, custom_researcher])

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
  
  # Execute the custom coordinator agent with the user's input
  result_event = custom_coordinator.run_task(
    session_id: session_id,
    user_input: user_input,
    session_service: session_service
  )
  
  # Display the result
  puts "\nResult:"
  puts "-" * 50
  puts result_event.content[:result]
  puts "-" * 50
end

puts "\nThank you for using the Multi-Agent Delegation Example!" 