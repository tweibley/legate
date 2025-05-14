#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of a Sequential Travel Planning Process Using Automatic Execution
# Run with: bundle exec ruby examples/travel_planner_auto_sequential.rb
#
# This example demonstrates how to create a sequential agent pattern where multiple specialized
# agents are executed in sequence automatically by the SequentialAgent class without explicit
# invocation of each sub-agent task.
#
# Key components of this example:
# 1. Multiple specialized agents: destination_research, itinerary_planner, budget_estimator, and trip_summarizer
# 2. A parent sequential agent that orchestrates the execution of the specialized agents
# 3. Each agent has its own output_key to store its results in the shared session state
# 4. The SequentialAgent class automatically handles the execution flow and data passing between agents
#
# The architecture follows these principles:
# - Each agent is fully specialized for its task
# - Agents share the same session, allowing them to access each other's outputs
# - The parent-child relationship is explicitly established through the sub_agents parameter
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

puts '=== Travel Planner Auto-Sequential Process Example ==='
puts 'This example demonstrates a sequence of specialized agents to plan a trip'
puts 'The SequentialAgent class automatically handles the execution flow and data passing.'

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

    First, analyze the destination information provided. Check the session state for the results from the destination_research agent.
    Then, use the 'echo' tool to output your response.

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

    First, analyze the destination and itinerary information provided. Check the session state for the results from the destination_research and itinerary_planner agents.
    Then, use the 'echo' tool to output your response.

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

    You are the final agent in a sequence of specialized travel planning agents. Your job is to summarize the outputs of the previous agents and create a final trip summary.

    Check the session state for the results from all previous agents (destination_research, itinerary_planner, and budget_estimator).
    Then, use the 'echo' tool to output your response.

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

# 5. Parent Sequential Agent Definition
travel_planner_def = ADK::AgentDefinition.new.define do |a|
  a.name :travel_planner
  a.description 'Orchestrates the complete travel planning process'
  a.instruction <<~INSTRUCTION
    You are a travel planning coordinator that will oversee the entire process of planning a trip.

    You will delegate specific tasks to specialized sub-agents in this sequence:
    1. Destination Research - The first agent will suggest suitable destinations based on user preferences
    2. Itinerary Planning - The second agent will create a detailed itinerary for the selected destination
    3. Budget Estimation - The third agent will calculate the estimated costs for the trip
    4. Trip Summary - The final agent will compile all information into a comprehensive travel plan

    Your job is to coordinate this process and ensure all agents have the information they need.
  INSTRUCTION
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
user_input = "I'd like to plan a relaxing vacation for early June. I enjoy nature, good food, and cultural experiences. My budget is moderate, and I prefer places with warm but not hot weather."

puts "Processing travel planning request..."
puts "User input: #{user_input}\n"

# Print the sequence information
puts "This will use a SequentialAgent to execute 4 specialized agents:"
puts "1. Destination Research → 2. Itinerary Planning → 3. Budget Estimation → 4. Trip Summary\n"

# Create a multi-spinner for tracking all processes
spinners = TTY::Spinner::Multi.new("[:spinner] Travel Planning Process", format: :dots, success_mark: "✅", error_mark: "❌")

# Create instances of all the individual sub-agents
destination_agent = ADK::Agent.new(definition: destination_agent_def, session_service: session_service)
itinerary_agent = ADK::Agent.new(definition: itinerary_agent_def, session_service: session_service)
budget_agent = ADK::Agent.new(definition: budget_agent_def, session_service: session_service)
summary_agent = ADK::Agent.new(definition: summary_agent_def, session_service: session_service)

# Add the echo tool to each agent
[destination_agent, itinerary_agent, budget_agent, summary_agent].each do |agent|
  agent.add_tool(ADK::Tools::Echo)
end

# Create the parent sequential agent instance with all sub-agents explicitly provided
travel_planner = ADK::Agents::SequentialAgent.new(
  definition: travel_planner_def,
  session_service: session_service,
  sub_agents: [destination_agent, itinerary_agent, budget_agent, summary_agent]
)

# Start all agents
puts "Starting all agents..."
destination_agent.start
itinerary_agent.start
budget_agent.start
summary_agent.start
travel_planner.start

# Create spinner for tracking progress
master_spinner = spinners.register("[:spinner] Total Progress")
master_spinner.auto_spin

# Create spinners for each sub-agent
destination_spinner = spinners.register("[:spinner] Destination Research")
itinerary_spinner = spinners.register("[:spinner] Itinerary Planning")
budget_spinner = spinners.register("[:spinner] Budget Estimation")
summary_spinner = spinners.register("[:spinner] Trip Summary")

# Start all spinners
destination_spinner.auto_spin
itinerary_spinner.auto_spin
budget_spinner.auto_spin
summary_spinner.auto_spin

# Run the sequential agent
begin
  # The SequentialAgent automatically runs all sub-agents in sequence
  # Each agent stores its output in the session state using its output_key
  # Subsequent agents can access previous agents' outputs from the session state
  result = travel_planner.run_task(
    session_id: session_id,
    user_input: user_input,
    session_service: session_service
  )

  if result.content[:status] == :error
    puts "Error in sequential execution: #{result.content[:error_message]}"
    master_spinner.error
    destination_spinner.error
    itinerary_spinner.error
    budget_spinner.error
    summary_spinner.error
    exit 1
  end

  # Mark all spinners as complete
  destination_spinner.success
  itinerary_spinner.success
  budget_spinner.success
  summary_spinner.success
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

  puts "Note: This example uses the built-in SequentialAgent to automatically execute all sub-agents in sequence."
  puts "The SequentialAgent class handles the flow of execution and ensures each agent has access to the outputs"
  puts "of previous agents through the shared session state, without requiring any custom implementation."
rescue StandardError => e
  puts "Error during execution: #{e.message}"
  puts e.backtrace.join("\n")
  master_spinner.error if master_spinner
  destination_spinner.error if destination_spinner
  itinerary_spinner.error if itinerary_spinner
  budget_spinner.error if budget_spinner
  summary_spinner.error if summary_spinner
  exit 1
end

puts "\n=== Travel Planner Example Complete ==="
