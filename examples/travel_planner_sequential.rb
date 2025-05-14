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

    First, analyze all the information provided from the previous steps. Then, use the 'echo' tool to output your response.

    Your echo response should follow this EXACT format:

    # COMPLETE TRAVEL PLAN: [DESTINATION]

    ## Destination Overview
    [Summarize key points about the destination from the research]

    ## Trip Highlights
    - [Highlight 1]
    - [Highlight 2]
    - [Highlight 3]

    ## Itinerary Summary
    - **Day 1**: [One-line summary of day 1 activities]
    - **Day 2**: [One-line summary of day 2 activities]
    - **Day 3**: [One-line summary of day 3 activities]

    ## Budget Snapshot
    - **Total Estimated Cost**: $[AMOUNT] USD
    - **Main Expenses**: [Brief note on biggest expenses]
    - **Savings Opportunities**: [Key money-saving tip]

    ## Final Recommendations
    [2-3 sentences with final personalized recommendations]
  INSTRUCTION
  a.model_name 'gemini-2.0-flash'
  a.output_key :trip_summary
  a.use_tool :echo
end

# Register all agents globally
ADK::GlobalDefinitionRegistry.register(destination_agent_def)
ADK::GlobalDefinitionRegistry.register(itinerary_agent_def)
ADK::GlobalDefinitionRegistry.register(budget_agent_def)
ADK::GlobalDefinitionRegistry.register(summary_agent_def)

# ----- Initialize and Run the Agents in Sequence -----

puts "\nStarting the specialized travel planning process..."

# Create an in-memory session service that all agents will share
session_service = ADK::SessionService::InMemory.new

# Create instances of all agents
destination_agent = ADK::Agent.new(definition: destination_agent_def, session_service: session_service)
itinerary_agent = ADK::Agent.new(definition: itinerary_agent_def, session_service: session_service)
budget_agent = ADK::Agent.new(definition: budget_agent_def, session_service: session_service)
summary_agent = ADK::Agent.new(definition: summary_agent_def, session_service: session_service)

# Create a session
session = session_service.create_session(app_name: 'travel_planner', user_id: 'example_user')
session_id = session.id
puts "Created session: #{session_id}\n\n"

# Define the travel planning request
user_input = "I'd like to plan a relaxing vacation for early June. I enjoy nature, good food, and cultural experiences. My budget is moderate, and I prefer places with warm but not hot weather."

puts "Processing travel planning request..."
puts "User input: #{user_input}\n"

# Print the sequence information
puts "This will sequentially execute 4 specialized agents:"
puts "1. Destination Research → 2. Itinerary Planning → 3. Budget Estimation → 4. Trip Summary\n"
puts "Starting the sequential process (this may take a minute)...\n"

# Start all agents
destination_agent.start
itinerary_agent.start
budget_agent.start
summary_agent.start

# Execute the agents in sequence
begin
  # Step 1: Destination Research
  puts "\nStep 1: Destination Research"
  destination_result = destination_agent.run_task(
    session_id: session_id,
    user_input: user_input,
    session_service: session_service
  )

  if destination_result.content[:status] == :error
    puts "Error in destination research: #{destination_result.content[:error_message]}"
    exit 1
  end

  destination_text = destination_result.content[:result]
  puts "Destination research completed."

  # Step 2: Itinerary Planning
  puts "\nStep 2: Itinerary Planning"
  itinerary_input = "#{user_input}\n\nBased on the destination research, here are the recommended destinations:\n\n#{destination_text}"
  itinerary_result = itinerary_agent.run_task(
    session_id: session_id,
    user_input: itinerary_input,
    session_service: session_service
  )

  if itinerary_result.content[:status] == :error
    puts "Error in itinerary planning: #{itinerary_result.content[:error_message]}"
    exit 1
  end

  itinerary_text = itinerary_result.content[:result]
  puts "Itinerary planning completed."

  # Step 3: Budget Estimation
  puts "\nStep 3: Budget Estimation"
  budget_input = "#{user_input}\n\nDestination and itinerary information:\n\n#{destination_text}\n\n#{itinerary_text}"
  budget_result = budget_agent.run_task(
    session_id: session_id,
    user_input: budget_input,
    session_service: session_service
  )

  if budget_result.content[:status] == :error
    puts "Error in budget estimation: #{budget_result.content[:error_message]}"
    exit 1
  end

  budget_text = budget_result.content[:result]
  puts "Budget estimation completed."

  # Step 4: Trip Summary
  puts "\nStep 4: Trip Summary"
  summary_input = "Create a comprehensive travel plan summary based on the following information:\n\n" +
                  "DESTINATION RESEARCH:\n#{destination_text}\n\n" +
                  "ITINERARY:\n#{itinerary_text}\n\n" +
                  "BUDGET:\n#{budget_text}"

  summary_result = summary_agent.run_task(
    session_id: session_id,
    user_input: summary_input,
    session_service: session_service
  )

  if summary_result.content[:status] == :error
    puts "Error in trip summary: #{summary_result.content[:error_message]}"
    exit 1
  end

  trip_summary = summary_result.content[:result]
  puts "Trip summary completed."

  # Display the final trip summary
  puts "\n=== Travel Planning Complete ===\n\n"
  puts "Final Trip Summary:"
  puts "----------------------"
  puts trip_summary
rescue StandardError => e
  puts "Error during execution: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end

puts "\n=== Travel Planner Example Complete ==="
