#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of a Sequential Travel Planning Process
# Run with: bundle exec ruby examples/travel_planner_sequential.rb
#
# This example demonstrates how to create a sequential agent pattern where multiple specialized
# agents are executed in sequence, with each agent handling a specific part of a larger task.
#
# Key components of this example:
# 1. Multiple specialized agents: destination_research, itinerary_planner, budget_estimator, and trip_summarizer
# 2. A parent sequential agent that orchestrates the execution of the specialized agents
# 3. Each agent has its own output_key to store its results in the shared session state
# 4. The sequential agent architecture allows complex workflows to be broken down into manageable steps
#
# The architecture follows these principles:
# - Each agent is fully specialized for its task
# - Agents share the same session, allowing them to access each other's outputs
# - The parent-child relationship is explicitly established through instance variables
# - The execution order is defined using sequential_sub_agents in the parent agent definition

require_relative '../lib/adk'
require_relative '../lib/adk/agents/sequential_agent' # Required for SequentialAgent

# Check if tty-spinner is installed
begin
  require 'tty-spinner'
rescue LoadError
  puts "The tty-spinner gem is required for this example."
  puts "Please install it with: gem install tty-spinner"
  puts "Or add it to your Gemfile and run: bundle install"
  exit 1
end

# Clear any existing registrations to avoid conflicts
ADK::GlobalDefinitionRegistry.instance_variable_set(:@definitions, {})

puts '=== Travel Planner Sequential Process Example ==='
puts 'This example demonstrates a sequence of specialized agents to plan a trip'

# Ensure the echo tool is registered - all agents will use this
unless ADK::GlobalToolManager.registered_tool_names.include?(:echo)
  ADK::GlobalToolManager.register_tool(ADK::Tools::Echo)
end

# Ensure delegate_task tool is registered for agent delegation
unless ADK::GlobalToolManager.registered_tool_names.include?(:delegate_task)
  ADK::GlobalToolManager.register_tool(ADK::Tools::AgentTool)
end

# ----- Define Specialized Agents -----

# 1. Destination Research Agent
destination_agent_def = ADK::AgentDefinition.new.define do |a|
  a.name :destination_research
  a.description 'Researches and suggests destination options based on user preferences'
  a.instruction <<~INSTRUCTION
    You are a destination research specialist. Your task is to analyze the user's preferences and suggest 2-3 suitable destinations.

    First, think about what destinations would be appropriate based on the user's preferences. Then, use the 'echo' tool to output your response.

    Your echo response should follow this EXACT format:

    # DESTINATION RECOMMENDATIONS

    Based on your preferences, here are the destinations I recommend:

    ## [Destination 1 Name]
    - **Location**: [Region/Country]
    - **Weather**: [Weather description for the time period]
    - **Highlights**: [3-4 key attractions or experiences]
    - **Best For**: [What makes this destination perfect for the user]

    ## [Destination 2 Name]
    - **Location**: [Region/Country]
    - **Weather**: [Weather description for the time period]
    - **Highlights**: [3-4 key attractions or experiences]
    - **Best For**: [What makes this destination perfect for the user]

    ## [Destination 3 Name] (optional)
    - **Location**: [Region/Country]
    - **Weather**: [Weather description for the time period]
    - **Highlights**: [3-4 key attractions or experiences]
    - **Best For**: [What makes this destination perfect for the user]

    # RECOMMENDATION SUMMARY
    [Brief explanation of why these destinations match the user's preferences]
  INSTRUCTION
  a.model_name 'gemini-2.0-flash'
  a.output_key :destination_results
  a.use_tool :echo
end

# 2. Itinerary Planning Agent
itinerary_agent_def = ADK::AgentDefinition.new.define do |a|
  a.name :itinerary_planner
  a.description 'Creates a detailed itinerary for the selected destination'
  a.instruction <<~INSTRUCTION
    You are an itinerary planner. Based on the destination information provided, create a 3-day itinerary for the most suitable destination.

    First, analyze the destination information provided. Then, use the 'echo' tool to output your response.

    Your echo response should follow this EXACT format:

    # 3-DAY ITINERARY FOR [DESTINATION]

    ## Day 1

    **Morning**
    - [Activity]: [Brief description]
    - [Activity]: [Brief description]

    **Afternoon**
    - [Activity]: [Brief description]
    - [Activity]: [Brief description]

    **Evening**
    - [Activity]: [Brief description]
    - [Activity]: [Brief description]

    ## Day 2

    **Morning**
    - [Activity]: [Brief description]
    - [Activity]: [Brief description]

    **Afternoon**
    - [Activity]: [Brief description]
    - [Activity]: [Brief description]

    **Evening**
    - [Activity]: [Brief description]
    - [Activity]: [Brief description]

    ## Day 3

    **Morning**
    - [Activity]: [Brief description]
    - [Activity]: [Brief description]

    **Afternoon**
    - [Activity]: [Brief description]
    - [Activity]: [Brief description]

    **Evening**
    - [Activity]: [Brief description]
    - [Activity]: [Brief description]

    # TRANSPORTATION TIPS
    [Brief notes on getting around the destination]
  INSTRUCTION
  a.model_name 'gemini-2.0-flash'
  a.output_key :itinerary_results
  a.use_tool :echo
end

# 3. Budget Estimation Agent
budget_agent_def = ADK::AgentDefinition.new.define do |a|
  a.name :budget_estimator
  a.description 'Provides cost estimates for the planned trip'
  a.instruction <<~INSTRUCTION
    You are a travel budget specialist. Based on the destination and activities in the itinerary, provide a detailed cost estimate.

    First, analyze the destination and itinerary information provided. Then, use the 'echo' tool to output your response.

    Your echo response should follow this EXACT format:

    # BUDGET ESTIMATE FOR [DESTINATION]

    ## Estimated Total: $[AMOUNT] USD

    ## Cost Breakdown

    **Flights**
    - Estimated cost: $[AMOUNT] USD
    - Notes: [Brief notes about flight options/assumptions]

    **Accommodation (3 nights)**
    - Estimated cost: $[AMOUNT] USD ($[AMOUNT]/night)
    - Type: [Hotel/Airbnb/etc.]
    - Notes: [Brief notes about accommodation options]

    **Daily Activities**
    - Estimated cost: $[AMOUNT] USD
    - Includes: [List of paid activities from itinerary]

    **Food & Dining**
    - Estimated cost: $[AMOUNT] USD ($[AMOUNT]/day)
    - Includes: [Assumptions about meals]

    **Local Transportation**
    - Estimated cost: $[AMOUNT] USD
    - Type: [Public transit/rental car/taxis/etc.]

    **Miscellaneous**
    - Estimated cost: $[AMOUNT] USD
    - Includes: [Souvenirs, tips, unexpected expenses, etc.]

    # MONEY-SAVING TIPS
    - [Tip 1]
    - [Tip 2]
    - [Tip 3]
  INSTRUCTION
  a.model_name 'gemini-2.0-flash'
  a.output_key :budget_results
  a.use_tool :echo
end

# 4. Trip Summary Agent
summary_agent_def = ADK::AgentDefinition.new.define do |a|
  a.name :trip_summarizer
  a.description 'Creates a comprehensive trip summary from all previous results'
  a.instruction <<~INSTRUCTION
    You are a travel summary specialist. Create a concise, well-formatted trip summary that brings together all the information from the destination research, itinerary, and budget.

    You are the final agent in a sequence of specialized travel planning agents. Your job is to summarize the outputs of the previous agents and create a final trip summary. The user input includes all previous agent outputs.

    First, analyze all the information provided from the previous steps. Then, use the 'echo' tool to output your response.

    Your echo response should follow this EXACT format:

    # COMPLETE TRAVEL PLAN

    ## Destination Overview
    [Summarize key points about the destination(s) discussed in previous steps]

    ## Trip Highlights
    - [Highlight 1]
    - [Highlight 2]
    - [Highlight 3]

    ## Budget Considerations
    - **Daily Budget**: $[AMOUNT] USD
    - **Main Expenses**: [Brief note on biggest expenses]
    - **Savings Opportunities**: [Key money-saving tip]

    ## Final Recommendations
    [2-3 sentences with final personalized recommendations]

    ## Additional Information
    This trip plan was created by a sequence of specialized agents:
    1. Destination Research - Analyzed preferences and suggested destinations
    2. Itinerary Planning - Created daily activities
    3. Budget Estimation - Estimated costs
    4. Trip Summary - Combined all information (this output)
  INSTRUCTION
  a.model_name 'gemini-2.0-flash'
  a.output_key :trip_summary
  a.use_tool :echo
end

# 5. NEW: Parent Sequential Agent Definition
travel_planner_def = ADK::AgentDefinition.new.define do |a|
  a.name :travel_planner
  a.description 'Orchestrates the complete travel planning process'
  a.instruction "This is a sequential agent that coordinates multiple specialized agents to plan a complete trip."
  a.model_name 'gemini-2.0-flash'
  a.output_key :complete_travel_plan
  a.agent_type :sequential # Important! This tells ADK to use SequentialAgent
  a.sequential_sub_agents :destination_research, :itinerary_planner, :budget_estimator, :trip_summarizer
end

# Register all agents globally
ADK::GlobalDefinitionRegistry.register(destination_agent_def)
ADK::GlobalDefinitionRegistry.register(itinerary_agent_def)
ADK::GlobalDefinitionRegistry.register(budget_agent_def)
ADK::GlobalDefinitionRegistry.register(summary_agent_def)
ADK::GlobalDefinitionRegistry.register(travel_planner_def)

# ----- Initialize and Run the Sequential Agent -----

puts "\nStarting the specialized travel planning process..."

# Create an in-memory session service that all agents will share
session_service = ADK::SessionService::InMemory.new

# Create session
session = session_service.create_session(app_name: 'travel_planner', user_id: 'example_user')
session_id = session.id
puts "Created session: #{session_id}\n\n"

# Define the travel planning request
base_user_input = "I'd like to plan a relaxing vacation for early June. I enjoy nature, good food, and cultural experiences. My budget is moderate, and I prefer places with warm but not hot weather."

# Add specialized prompts for each agent to help them understand their roles better
# This would typically be handled by the agent instructions, but we'll make it explicit
# in the user input to help the demo function correctly
user_input = <<~INPUT
  #{base_user_input}

  IMPORTANT CONTEXT: This request will be processed by a sequence of specialized agents:
  1. DESTINATION RESEARCH: You will research and suggest 2-3 suitable destinations matching my preferences
  2. ITINERARY PLANNING: You will create a detailed day-by-day itinerary for the best option
  3. BUDGET ESTIMATION: You will estimate costs for the trip
  4. TRIP SUMMARY: You will combine all information into a final travel plan
  5. USE US DOLLARS FOR ALL MONEY ESTIMATES

  Please follow your specific role in this sequence.
INPUT

puts "Processing travel planning request..."
puts "User input: #{base_user_input}\n"

# Print the sequence information
puts "This will use a SequentialAgent to execute 4 specialized agents:"
puts "1. Destination Research → 2. Itinerary Planning → 3. Budget Estimation → 4. Trip Summary\n"

# Create a multi-spinner for tracking all processes
spinners = TTY::Spinner::Multi.new("[:spinner] Travel Planning Process", format: :dots, success_mark: "✅", error_mark: "❌")

# First, ensure the echo tool is registered globally
puts "Ensuring the Echo tool is globally registered..."
unless ADK::GlobalToolManager.registered_tool_names.include?(:echo)
  ADK::GlobalToolManager.register_tool(ADK::Tools::Echo)
end

# Create instances of all the individual sub-agents
destination_agent = ADK::Agent.new(definition: destination_agent_def, session_service: session_service)
itinerary_agent = ADK::Agent.new(definition: itinerary_agent_def, session_service: session_service)
budget_agent = ADK::Agent.new(definition: budget_agent_def, session_service: session_service)
summary_agent = ADK::Agent.new(definition: summary_agent_def, session_service: session_service)

# Explicitly add the echo tool to each agent
puts "Adding Echo tool to each agent..."
[destination_agent, itinerary_agent, budget_agent, summary_agent].each do |agent|
  agent.add_tool(ADK::Tools::Echo)
end

# Create the parent sequential agent instance with all sub-agents explicitly provided
travel_planner = ADK::Agents::SequentialAgent.new(
  definition: travel_planner_def,
  session_service: session_service,
  sub_agents: [destination_agent, itinerary_agent, budget_agent, summary_agent]
)

# Define a custom wrapper class that enhances the input for each agent
# This helps demonstrate how a sequential agent can be customized
class TravelPlannerSequentialAgent
  def initialize(sequential_agent)
    @sequential_agent = sequential_agent
    @sub_agents = sequential_agent.instance_variable_get(:@sub_agents) # Access private variable
  end

  def start
    @sequential_agent.start
  end

  def run_task(session_id:, user_input:, session_service:, spinners:)
    # First, store the original user input in the session state
    session_service.set_state(session_id: session_id, key: :original_request, value: user_input)

    # Record the user's request as an event
    user_event = ADK::Event.new(role: :user, content: user_input)
    session_service.append_event(session_id: session_id, event: user_event)

    puts "\nExecuting each agent in sequence with specialized context..."

    # 1. Destination Research - First Agent gets the original request with emphasis on destinations
    destination_spinner = spinners.register("[:spinner] Destination Research")
    destination_spinner.auto_spin

    destination_input = "#{user_input}\n\nYou are the DESTINATION RESEARCH agent. Your task is to suggest 2-3 destinations that match the preferences."
    destination_result = @sub_agents[0].run_task(
      session_id: session_id,
      user_input: destination_input,
      session_service: session_service
    )
    destination_spinner.success

    # 2. Itinerary Planning - Gets the destinations and creates an itinerary
    itinerary_spinner = spinners.register("[:spinner] Itinerary Planning")
    itinerary_spinner.auto_spin

    destination_data = session_service.get_state(session_id: session_id, key: :destination_results)
    itinerary_input = "#{user_input}\n\nYou are the ITINERARY PLANNING agent. Your task is to create a detailed 3-day itinerary.\n\nPrevious agent output:\n#{destination_data ? destination_data['result'] : 'No destination data available'}"
    itinerary_result = @sub_agents[1].run_task(
      session_id: session_id,
      user_input: itinerary_input,
      session_service: session_service
    )
    itinerary_spinner.success

    # 3. Budget Estimation - Gets the itinerary and estimates costs
    budget_spinner = spinners.register("[:spinner] Budget Estimation")
    budget_spinner.auto_spin

    itinerary_data = session_service.get_state(session_id: session_id, key: :itinerary_results)
    budget_input = "#{user_input}\n\nYou are the BUDGET ESTIMATION agent. Your task is to provide a detailed cost breakdown.\n\nPrevious agent outputs:\n#{destination_data ? destination_data['result'] : 'No destination data available'}\n#{itinerary_data ? itinerary_data['result'] : 'No itinerary data available'}"
    budget_result = @sub_agents[2].run_task(
      session_id: session_id,
      user_input: budget_input,
      session_service: session_service
    )
    budget_spinner.success

    # 4. Trip Summary - Gets all previous data and creates a final summary
    summary_spinner = spinners.register("[:spinner] Trip Summary")
    summary_spinner.auto_spin

    budget_data = session_service.get_state(session_id: session_id, key: :budget_results)
    summary_input = "#{user_input}\n\nYou are the TRIP SUMMARY agent. Your task is to create a comprehensive summary of all previous results.\n\nPrevious agent outputs:\n#{destination_data ? destination_data['result'] : 'No destination data available'}\n#{itinerary_data ? itinerary_data['result'] : 'No itinerary data available'}\n#{budget_data ? budget_data['result'] : 'No budget data available'}"
    summary_result = @sub_agents[3].run_task(
      session_id: session_id,
      user_input: summary_input,
      session_service: session_service
    )
    summary_spinner.success

    # Return the final summary result
    return summary_result
  end
end

# Create and use the enhanced travel planner
enhanced_travel_planner = TravelPlannerSequentialAgent.new(travel_planner)

# Start all agents
puts "Starting all agents..."
destination_agent.start
itinerary_agent.start
budget_agent.start
summary_agent.start
enhanced_travel_planner.start

# Create master spinner
master_spinner = spinners.register("[:spinner] Total Progress")
master_spinner.auto_spin

# Run the sequential agent
begin
  # The SequentialAgent automatically runs all sub-agents in sequence.
  # Each agent stores its output in the session state using its output_key.
  # Subsequent agents can access previous agents' outputs by retrieving values from
  # the session state. This is handled automatically by the SequentialAgent class.
  result = enhanced_travel_planner.run_task(
    session_id: session_id,
    user_input: user_input,
    session_service: session_service,
    spinners: spinners
  )

  if result.content[:status] == :error
    puts "Error in sequential execution: #{result.content[:error_message]}"
    master_spinner.error
    exit 1
  end

  # Mark the master spinner as complete
  master_spinner.success

  # Get all session data directly
  session = session_service.get_session(session_id: session_id)

  # Print the raw session state for debugging purposes
  puts "\nDEBUG: Session State Contents"
  puts "----------------------------"
  session.state.each do |key, value|
    puts "#{key}: #{value.inspect[0..200]}..." if value
  end
  puts

  # Display the final trip summary
  puts "\n=== Travel Planning Complete ===\n\n"

  puts "SEQUENTIAL AGENT RESULTS"
  puts "------------------------"
  puts "The sequential agent successfully executed all sub-agents in sequence.\n\n"

  puts "STEP 1: DESTINATION RESEARCH"
  puts "----------------------------"
  if session.state[:destination_results] && session.state[:destination_results]["result"]
    puts session.state[:destination_results]["result"]
  else
    puts "(No destination research results available)"
  end
  puts "\n"

  puts "STEP 2: ITINERARY PLANNING"
  puts "-------------------------"
  if session.state[:itinerary_results] && session.state[:itinerary_results]["result"]
    puts session.state[:itinerary_results]["result"]
  else
    puts "(No itinerary planning results available)"
  end
  puts "\n"

  puts "STEP 3: BUDGET ESTIMATION"
  puts "-------------------------"
  if session.state[:budget_results] && session.state[:budget_results]["result"]
    puts session.state[:budget_results]["result"]
  else
    puts "(No budget estimation results available)"
  end
  puts "\n"

  puts "STEP 4: FINAL TRAVEL SUMMARY"
  puts "---------------------------"
  if session.state[:trip_summary] && session.state[:trip_summary]["result"]
    puts session.state[:trip_summary]["result"]
  else
    puts "(No trip summary available)"
  end
  puts "\n"

  puts "Note: This example uses a custom wrapper around SequentialAgent to make the sub-agent sequence"
  puts "more explicit and to clearly demonstrate how data can be passed between agents."
  puts "In production, the ADK::Agents::SequentialAgent class would manage this automatically without"
  puts "requiring a custom implementation. This approach is just for demonstration purposes."
  puts "The example shows that agents can either use the built-in sequential processing or"
  puts "implement custom orchestration logic as shown here."
rescue StandardError => e
  puts "Error during execution: #{e.message}"
  puts e.backtrace.join("\n")
  master_spinner.error if master_spinner
  exit 1
end

puts "\n=== Travel Planner Example Complete ==="
