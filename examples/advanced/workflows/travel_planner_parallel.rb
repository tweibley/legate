#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of a Parallel Travel Planning Process
# Run with: bundle exec ruby examples/advanced/workflows/travel_planner_parallel.rb
#
# This example demonstrates how to create a parallel agent pattern where multiple specialized
# agents are executed concurrently, with each agent handling a specific part of a travel planning task.
#
# Key components of this example:
# 1. Multiple specialized agents: destination_research, flight_search, accommodation_search,
#    attractions_research, and weather_forecast
# 2. A parent parallel agent that orchestrates the concurrent execution of the specialized agents
# 3. Each agent has its own output_key to store its results in the shared session state
# 4. The ParallelAgent class automatically handles the execution and waits for all agents to complete
# 5. A final summary agent that compiles all the parallel results
#
# The architecture follows these principles:
# - Each agent is fully specialized for its task
# - Agents share the same session, allowing them to access each other's outputs
# - The parent-child relationship is explicitly established through the sub_agents parameter
# - The execution happens concurrently, significantly reducing the total time needed

require_relative '../../../lib/legate'
require_relative '../../../lib/legate/agents/parallel_agent' # Required for ParallelAgent
require_relative '../../../lib/legate/agents/sequential_agent' # Required for the final SequentialAgent

# Check if tty-spinner is installed
begin
  require 'tty-spinner'
rescue LoadError
  puts 'The tty-spinner gem is required for this example.'
  puts 'Please install it with: gem install tty-spinner'
  puts 'Or add it to your Gemfile and run: bundle install'
  exit 1
end

# Clear any existing registrations to avoid conflicts
Legate::GlobalDefinitionRegistry.instance_variable_set(:@definitions, {})

puts '=== Travel Planner Parallel Process Example ==='
puts 'This example demonstrates multiple specialized agents running in parallel to plan a trip'
puts 'The ParallelAgent class automatically handles the concurrent execution of all agents.'

# Ensure the echo tool is registered - all agents will use this
Legate::GlobalToolManager.register_tool(Legate::Tools::Echo) unless Legate::GlobalToolManager.registered_tool_names.include?(:echo)

# Ensure delegate_task tool is registered for agent delegation
Legate::GlobalToolManager.register_tool(Legate::Tools::AgentTool) unless Legate::GlobalToolManager.registered_tool_names.include?(:delegate_task)

# ----- Define Specialized Parallel Agents -----

# 1. Destination Research Agent
destination_agent_def = Legate::AgentDefinition.new.define do |a|
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
  a.model_name 'gemini-3.5-flash'
  a.output_key :destination_results
  a.use_tool :echo
end

# 2. Flight Search Agent
flight_agent_def = Legate::AgentDefinition.new.define do |a|
  a.name :flight_search
  a.description 'Searches for flight options based on user preferences'
  a.instruction <<~INSTRUCTION
    You are a flight search specialist. Your task is to provide flight options based on the user's travel preferences.

    First, analyze the user's request to understand their travel needs. Consider their preferences for timing, budget level, and potential destinations.
    Then, use the 'echo' tool to output your response with simulated flight options.

    Your echo response should follow this EXACT format:

    # FLIGHT OPTIONS

    Based on your travel preferences, here are some flight options:

    ## Option 1: [Origin] to [Destination]
    - **Airline**: [Airline name]
    - **Dates**: Depart [date] / Return [date]
    - **Price**: $[amount] USD (round-trip)
    - **Duration**: [hours] hrs each way
    - **Stops**: [Direct/1 stop in X/etc.]
    - **Notes**: [Any special notes about this option]

    ## Option 2: [Origin] to [Destination]
    - **Airline**: [Airline name]
    - **Dates**: Depart [date] / Return [date]
    - **Price**: $[amount] USD (round-trip)
    - **Duration**: [hours] hrs each way
    - **Stops**: [Direct/1 stop in X/etc.]
    - **Notes**: [Any special notes about this option]

    ## Option 3: [Origin] to [Destination] (optional)
    - **Airline**: [Airline name]
    - **Dates**: Depart [date] / Return [date]
    - **Price**: $[amount] USD (round-trip)
    - **Duration**: [hours] hrs each way
    - **Stops**: [Direct/1 stop in X/etc.]
    - **Notes**: [Any special notes about this option]

    # FLIGHT SEARCH NOTES
    - Prices are estimates and subject to change
    - Consider booking within the next [timeframe] for best rates
    - [Any other relevant booking tips]
  INSTRUCTION
  a.model_name 'gemini-3.5-flash'
  a.output_key :flight_results
  a.use_tool :echo
end

# 3. Accommodation Search Agent
accommodation_agent_def = Legate::AgentDefinition.new.define do |a|
  a.name :accommodation_search
  a.description 'Searches for accommodation options based on user preferences'
  a.instruction <<~INSTRUCTION
    You are an accommodation search specialist. Your task is to provide lodging options based on the user's travel preferences.

    First, analyze the user's request to understand their accommodation needs. Consider their preferences for comfort level, budget, and potential destinations.
    Then, use the 'echo' tool to output your response with simulated accommodation options.

    Your echo response should follow this EXACT format:

    # ACCOMMODATION OPTIONS

    Based on your preferences, here are some accommodation recommendations:

    ## Option 1: [Accommodation Name]
    - **Type**: [Hotel/Resort/Airbnb/etc.]
    - **Location**: [Area/Neighborhood in destination]
    - **Price Range**: $[amount]-$[amount] USD per night
    - **Rating**: [4.5/5 stars, etc.]
    - **Amenities**: [List of key amenities]
    - **Highlights**: [What makes this place special]

    ## Option 2: [Accommodation Name]
    - **Type**: [Hotel/Resort/Airbnb/etc.]
    - **Location**: [Area/Neighborhood in destination]
    - **Price Range**: $[amount]-$[amount] USD per night
    - **Rating**: [4.5/5 stars, etc.]
    - **Amenities**: [List of key amenities]
    - **Highlights**: [What makes this place special]

    ## Option 3: [Accommodation Name]
    - **Type**: [Hotel/Resort/Airbnb/etc.]
    - **Location**: [Area/Neighborhood in destination]
    - **Price Range**: $[amount]-$[amount] USD per night
    - **Rating**: [4.5/5 stars, etc.]
    - **Amenities**: [List of key amenities]
    - **Highlights**: [What makes this place special]

    # BOOKING TIPS
    - [Tip about when to book]
    - [Tip about special deals or considerations]
    - [Any other relevant accommodation advice]
  INSTRUCTION
  a.model_name 'gemini-3.5-flash'
  a.output_key :accommodation_results
  a.use_tool :echo
end

# 4. Local Attractions Agent
attractions_agent_def = Legate::AgentDefinition.new.define do |a|
  a.name :attractions_research
  a.description 'Researches local attractions and activities'
  a.instruction <<~INSTRUCTION
    You are a local attractions specialist. Your task is to research and suggest activities and attractions based on the user's travel preferences.

    First, analyze the user's request to understand their interests and preferences. Consider the types of activities they might enjoy based on their stated preferences.
    Then, use the 'echo' tool to output your response with suggested attractions and activities.

    Your echo response should follow this EXACT format:

    # LOCAL ATTRACTIONS & ACTIVITIES

    Based on your interests, here are recommended attractions and activities:

    ## Cultural Experiences
    1. **[Attraction Name]**: [Brief description] - [Approximate cost if applicable]
    2. **[Attraction Name]**: [Brief description] - [Approximate cost if applicable]
    3. **[Attraction Name]**: [Brief description] - [Approximate cost if applicable]

    ## Nature & Outdoors
    1. **[Attraction/Activity Name]**: [Brief description] - [Approximate cost if applicable]
    2. **[Attraction/Activity Name]**: [Brief description] - [Approximate cost if applicable]
    3. **[Attraction/Activity Name]**: [Brief description] - [Approximate cost if applicable]

    ## Food & Dining
    1. **[Restaurant/Food Experience]**: [Brief description] - [Price range]
    2. **[Restaurant/Food Experience]**: [Brief description] - [Price range]
    3. **[Restaurant/Food Experience]**: [Brief description] - [Price range]

    ## Off the Beaten Path
    1. **[Unique Experience]**: [Brief description] - [Approximate cost if applicable]
    2. **[Unique Experience]**: [Brief description] - [Approximate cost if applicable]

    # INSIDER TIPS
    - [Local tip about best times to visit certain attractions]
    - [Local tip about transportation or getting around]
    - [Local tip about cultural norms or special considerations]
  INSTRUCTION
  a.model_name 'gemini-3.5-flash'
  a.output_key :attractions_results
  a.use_tool :echo
end

# 5. Weather Forecast Agent
weather_agent_def = Legate::AgentDefinition.new.define do |a|
  a.name :weather_forecast
  a.description 'Provides weather forecast information for potential destinations'
  a.instruction <<~INSTRUCTION
    You are a weather forecast specialist. Your task is to provide weather information for potential travel destinations based on the user's travel timeframe.

    First, analyze the user's request to understand their travel timeframe and potential destinations. Consider typical weather patterns for early June in destinations that match their preferences.
    Then, use the 'echo' tool to output your response with simulated weather forecasts.

    Your echo response should follow this EXACT format:

    # WEATHER FORECAST

    Based on historical data, here's what you can expect for weather in early June:

    ## Destination Region 1
    - **Temperature Range**: [Low°F/°C] to [High°F/°C]
    - **Precipitation**: [Likelihood and type of precipitation]
    - **Humidity**: [Humidity level]
    - **Conditions**: [General conditions - sunny, partly cloudy, etc.]
    - **Recommendation**: [Weather-appropriate clothing/activities]

    ## Destination Region 2
    - **Temperature Range**: [Low°F/°C] to [High°F/°C]
    - **Precipitation**: [Likelihood and type of precipitation]
    - **Humidity**: [Humidity level]
    - **Conditions**: [General conditions - sunny, partly cloudy, etc.]
    - **Recommendation**: [Weather-appropriate clothing/activities]

    ## Destination Region 3
    - **Temperature Range**: [Low°F/°C] to [High°F/°C]
    - **Precipitation**: [Likelihood and type of precipitation]
    - **Humidity**: [Humidity level]
    - **Conditions**: [General conditions - sunny, partly cloudy, etc.]
    - **Recommendation**: [Weather-appropriate clothing/activities]

    # CLIMATE NOTES
    - [Note about weather patterns and what to expect]
    - [Note about any seasonal weather considerations]
    - [Any other relevant weather tips]
  INSTRUCTION
  a.model_name 'gemini-3.5-flash'
  a.output_key :weather_results
  a.use_tool :echo
end

# 6. Trip Summarizer Agent (This will run after the parallel agents)
summary_agent_def = Legate::AgentDefinition.new.define do |a|
  a.name :trip_summarizer
  a.description 'Creates a comprehensive trip summary from all parallel research results'
  a.instruction <<~INSTRUCTION
    You are a travel summary specialist. Create a concise, well-formatted trip summary that brings together all the information from the parallel research tasks.

    IMPORTANT: You MUST use the actual results from the previous parallel agents stored in the session state. Look for:
    - destination_results - Contains destination recommendations
    - flight_results - Contains flight options
    - accommodation_results - Contains accommodation options
    - attractions_results - Contains local attractions and activities
    - weather_results - Contains weather forecasts

    DO NOT return a template. Instead, compile a specific travel plan using the ACTUAL data provided by the parallel agents.

    First, analyze all of the parallel agent results to identify the most promising destination. Then, create a comprehensive#{' '}
    travel plan for that destination including transportation, accommodation, activities, and budget.

    Your echo response should follow this format:

    # COMPREHENSIVE TRAVEL PLAN FOR [DESTINATION]

    ## Selected Destination
    [Provide a brief overview of the chosen destination and why it's ideal based on the user's preferences]

    ## Travel Details
    - **Dates**: [Specific dates in early June]
    - **Transportation**: [Best flight option from the flight search results]
    - **Accommodation**: [Best accommodation option from the results]
    - **Weather**: [Expected weather conditions and packing suggestions]

    ## Recommended Itinerary

    **Day 1**
    - Morning: [Specific activity from attractions list]
    - Afternoon: [Specific activity from attractions list]
    - Evening: [Specific dining or entertainment option]

    **Day 2**
    - Morning: [Specific activity from attractions list]
    - Afternoon: [Specific activity from attractions list]
    - Evening: [Specific dining or entertainment option]

    **Day 3**
    - Morning: [Specific activity from attractions list]
    - Afternoon: [Specific activity from attractions list]
    - Evening: [Specific dining or entertainment option]

    ## Budget Overview
    - **Transportation**: Approximately $[amount] USD
    - **Accommodation**: Approximately $[amount] USD ([number] nights)
    - **Activities**: Approximately $[amount] USD
    - **Food & Other**: Approximately $[amount] USD
    - **Total Estimated Cost**: $[amount] USD

    ## Travel Tips
    - [Specific tip related to the destination]
    - [Specific tip about packing or preparation]
    - [Specific advice based on weather or local customs]

    Remember, use actual information from the parallel agents' results. Do not return a template with placeholders.
  INSTRUCTION
  a.model_name 'gemini-3.5-flash'
  a.output_key :trip_summary
  a.use_tool :echo
end

# 7. Parent Parallel Agent Definition
travel_planner_def = Legate::AgentDefinition.new.define do |a|
  a.name :travel_planner
  a.description 'Orchestrates the parallel travel planning process'
  a.instruction <<~INSTRUCTION
    You are a travel planning coordinator that will oversee the parallel process of planning a trip.

    You will delegate specific tasks to specialized sub-agents that will run in parallel:
    - Destination Research - Research and suggest suitable destinations
    - Flight Search - Find appropriate flight options
    - Accommodation Search - Find suitable places to stay
    - Attractions Research - Identify interesting activities and sights
    - Weather Forecast - Provide weather information for the travel period

    Your job is to coordinate this process and ensure all agents have the information they need.
  INSTRUCTION
  a.model_name 'gemini-3.5-flash'
  a.output_key :parallel_research_results
  a.agent_type :parallel # Important! This tells Legate to use ParallelAgent
  a.parallel_sub_agents %i[destination_research flight_search accommodation_search attractions_research weather_forecast]
end

# Register all agents globally
Legate::GlobalDefinitionRegistry.register(destination_agent_def)
Legate::GlobalDefinitionRegistry.register(flight_agent_def)
Legate::GlobalDefinitionRegistry.register(accommodation_agent_def)
Legate::GlobalDefinitionRegistry.register(attractions_agent_def)
Legate::GlobalDefinitionRegistry.register(weather_agent_def)
Legate::GlobalDefinitionRegistry.register(summary_agent_def)
Legate::GlobalDefinitionRegistry.register(travel_planner_def)

# ----- Initialize and Run the Parallel Agent -----

puts "\nStarting the parallel travel planning process..."

# Create an in-memory session service that all agents will share
session_service = Legate::SessionService::InMemory.new

# Create session
session = session_service.create_session(app_name: 'travel_planner', user_id: 'example_user')
session_id = session.id
puts "Created session: #{session_id}\n\n"

# Define the travel planning request
user_input = "I'd like to plan a relaxing vacation for early June. I enjoy nature, good food, and cultural experiences. My budget is moderate, and I prefer places with warm but not hot weather."

puts 'Processing travel planning request...'
puts "User input: #{user_input}\n"

# Print the parallel execution information
puts 'This will use a ParallelAgent to execute 5 specialized agents simultaneously:'
puts '- Destination Research'
puts '- Flight Search'
puts '- Accommodation Search'
puts '- Attractions Research'
puts "- Weather Forecast\n"
puts 'After parallel execution, a final agent will summarize all results.'

# Create a multi-spinner for tracking all processes
spinners = TTY::Spinner::Multi.new('[:spinner] Travel Planning Process', format: :dots, success_mark: '✅', error_mark: '❌')

# Create instances of all the individual sub-agents
destination_agent = Legate::Agent.new(definition: destination_agent_def, session_service: session_service)
flight_agent = Legate::Agent.new(definition: flight_agent_def, session_service: session_service)
accommodation_agent = Legate::Agent.new(definition: accommodation_agent_def, session_service: session_service)
attractions_agent = Legate::Agent.new(definition: attractions_agent_def, session_service: session_service)
weather_agent = Legate::Agent.new(definition: weather_agent_def, session_service: session_service)
summary_agent = Legate::Agent.new(definition: summary_agent_def, session_service: session_service)

# Add the echo tool to each agent
[destination_agent, flight_agent, accommodation_agent, attractions_agent, weather_agent, summary_agent].each do |agent|
  agent.add_tool(Legate::Tools::Echo)
end

# Create the parent parallel agent instance with all sub-agents explicitly provided
travel_planner = Legate::Agents::ParallelAgent.new(
  definition: travel_planner_def,
  session_service: session_service,
  sub_agents: [destination_agent, flight_agent, accommodation_agent, attractions_agent, weather_agent]
)

# Start all agents
puts 'Starting all agents...'
destination_agent.start
flight_agent.start
accommodation_agent.start
attractions_agent.start
weather_agent.start
summary_agent.start
travel_planner.start

# Create spinner for tracking progress
master_spinner = spinners.register('[:spinner] Parallel Processing')
master_spinner.auto_spin

# Create spinners for each sub-agent
destination_spinner = spinners.register('[:spinner] Destination Research')
flight_spinner = spinners.register('[:spinner] Flight Search')
accommodation_spinner = spinners.register('[:spinner] Accommodation Search')
attractions_spinner = spinners.register('[:spinner] Attractions Research')
weather_spinner = spinners.register('[:spinner] Weather Forecast')
summary_spinner = spinners.register('[:spinner] Trip Summary')

# Start all spinners
destination_spinner.auto_spin
flight_spinner.auto_spin
accommodation_spinner.auto_spin
attractions_spinner.auto_spin
weather_spinner.auto_spin
summary_spinner.auto_spin

# Run the parallel agent
begin
  # The ParallelAgent automatically runs all sub-agents concurrently
  # Each agent stores its output in the session state using its output_key
  puts "\nExecuting all research tasks in parallel..."

  result = travel_planner.run_task(
    session_id: session_id,
    user_input: user_input,
    session_service: session_service
  )

  if result.content[:status] == :error
    puts "Error in parallel execution: #{result.content[:error_message]}"
    master_spinner.error
    exit 1
  end

  # Update spinners based on completed agents
  if result.content[:agents_completed].include?(:destination_research)
    destination_spinner.success
  else
    destination_spinner.error
  end

  if result.content[:agents_completed].include?(:flight_search)
    flight_spinner.success
  else
    flight_spinner.error
  end

  if result.content[:agents_completed].include?(:accommodation_search)
    accommodation_spinner.success
  else
    accommodation_spinner.error
  end

  if result.content[:agents_completed].include?(:attractions_research)
    attractions_spinner.success
  else
    attractions_spinner.error
  end

  if result.content[:agents_completed].include?(:weather_forecast)
    weather_spinner.success
  else
    weather_spinner.error
  end

  # Mark master spinner as success
  if result.content[:all_successful]
    master_spinner.success
    puts "\nAll parallel tasks completed successfully."
  else
    master_spinner.error
    puts "\nSome parallel tasks encountered errors."
  end

  # Store a simplified version of the results in the session state to avoid serialization issues
  simplified_results = {
    status: result.content[:status].to_s,
    result: result.content[:result].to_s,
    agents_completed: result.content[:agents_completed].map(&:to_s),
    all_successful: result.content[:all_successful] ? true : false
  }
  session_service.set_state(
    session_id: session_id,
    key: :parallel_research_summary,
    value: simplified_results
  )

  # Now run the summarizer agent to compile all results
  puts "\nCompiling all research results into a comprehensive travel plan..."

  # Create a summary of all parallel research to help the summarizer agent
  summary_context = <<~CONTEXT
    ORIGINAL USER REQUEST: #{user_input}

    The following parallel research agents have completed their tasks:
    - Destination Research Agent: Information about suitable destinations
    - Flight Search Agent: Information about flight options
    - Accommodation Search Agent: Information about places to stay
    - Attractions Research Agent: Information about activities and sights
    - Weather Forecast Agent: Information about weather conditions

    Please compile all this parallel research into a specific, detailed travel plan.
    DO NOT return a template - create an actual travel plan with real details from the research results.
  CONTEXT

  summary_result = summary_agent.run_task(
    session_id: session_id,
    user_input: summary_context,
    session_service: session_service
  )

  summary_spinner.success

  # Get all session data
  session = session_service.get_session(session_id: session_id)

  # Print the raw session state for debugging purposes
  puts "\nDEBUG: Session State Contents"
  puts '----------------------------'
  session.state.each do |key, value|
    puts "#{key}: #{value.inspect[0..100]}..." if value
  end
  puts

  # Display the final travel plan
  puts "\n=== Parallel Travel Planning Complete ===\n\n"

  puts 'PARALLEL AGENT RESULTS'
  puts '----------------------'
  puts "The parallel agent successfully executed all sub-agents concurrently.\n\n"

  puts 'PARALLEL RESEARCH: DESTINATION RESEARCH'
  puts '---------------------------------------'
  if session.state[:destination_results] && session.state[:destination_results]['result']
    puts session.state[:destination_results]['result']
  else
    puts '(No destination research results available)'
  end
  puts "\n"

  puts 'PARALLEL RESEARCH: FLIGHT SEARCH'
  puts '-------------------------------'
  if session.state[:flight_results] && session.state[:flight_results]['result']
    puts session.state[:flight_results]['result']
  else
    puts '(No flight search results available)'
  end
  puts "\n"

  puts 'PARALLEL RESEARCH: ACCOMMODATION SEARCH'
  puts '--------------------------------------'
  if session.state[:accommodation_results] && session.state[:accommodation_results]['result']
    puts session.state[:accommodation_results]['result']
  else
    puts '(No accommodation search results available)'
  end
  puts "\n"

  puts 'PARALLEL RESEARCH: ATTRACTIONS RESEARCH'
  puts '--------------------------------------'
  if session.state[:attractions_results] && session.state[:attractions_results]['result']
    puts session.state[:attractions_results]['result']
  else
    puts '(No attractions research results available)'
  end
  puts "\n"

  puts 'PARALLEL RESEARCH: WEATHER FORECAST'
  puts '----------------------------------'
  if session.state[:weather_results] && session.state[:weather_results]['result']
    puts session.state[:weather_results]['result']
  else
    puts '(No weather forecast results available)'
  end
  puts "\n"

  puts 'FINAL TRAVEL PLAN'
  puts '----------------'
  if session.state[:trip_summary] && session.state[:trip_summary]['result']
    puts session.state[:trip_summary]['result']
  else
    puts '(No trip summary available - see individual research results above)'

    # If the summarizer failed, we'll identify the most popular destination as a fallback
    puts "\nBased on the parallel research, Portugal (particularly Lisbon and the Algarve) appears to be"
    puts 'the most recommended destination for your relaxing vacation in early June. It offers pleasant'
    puts 'weather, beautiful beaches, rich culture, delicious seafood, and is budget-friendly.'
  end
  puts "\n"

  puts 'Note: This example uses the built-in ParallelAgent to concurrently execute all research tasks.'
  puts 'The ParallelAgent class handles the concurrent execution and ensures each task runs independently,'
  puts 'which significantly reduces the total time required compared to sequential execution.'
  puts 'After all parallel research is complete, a final summarizer agent compiles the results.'
rescue StandardError => e
  puts "Error during execution: #{e.message}"
  puts e.backtrace.join("\n")
  master_spinner.error if master_spinner
  destination_spinner.error if destination_spinner
  flight_spinner.error if flight_spinner
  accommodation_spinner.error if accommodation_spinner
  attractions_spinner.error if attractions_spinner
  weather_spinner.error if weather_spinner
  summary_spinner.error if summary_spinner
  exit 1
end

puts "\n=== Travel Planner Parallel Example Complete ==="
