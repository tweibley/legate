# frozen_string_literal: true

# Example demonstrating the ADK::Agents::LoopAgent which executes sub-agents in a loop
# until a termination condition is met or max iterations are reached.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'adk'
require 'adk/agents/loop_agent'

# First, define sub-agents that will be used in the loop

# 1. Counter agent - increments a counter in session state
counter_agent = ADK::AgentDefinition.new.define do |a|
  a.name :counter_agent
  a.description 'Increments a counter in session state'
  a.instruction 'You increment a counter and report the new count.'
  a.use_tool :echo
  a.output_key :counter_result
end

# Register the agent definition so it can be found by name
ADK::GlobalDefinitionRegistry.register(counter_agent)

# 2. Check condition agent - examines count and decides if we need to continue
condition_agent = ADK::AgentDefinition.new.define do |a|
  a.name :condition_agent
  a.description 'Checks if loop should continue based on count'
  a.instruction 'Check the counter and set done to true if target is reached.'
  a.use_tool :echo
  a.output_key :done
end

# Register the agent definition
ADK::GlobalDefinitionRegistry.register(condition_agent)

# Now define the loop agent that uses the sub-agents
loop_agent = ADK::AgentDefinition.new.define do |a|
  a.name :loop_demo_agent
  a.description 'Demonstrates loop agent functionality'
  a.instruction 'You run a loop that counts until a condition is met.'
  a.agent_type :loop # This is important - specifies this is a loop agent

  # Sub-agents to execute in each loop iteration (in sequence)
  a.loop_sub_agents [:counter_agent, :condition_agent]

  # Maximum number of iterations (safety valve)
  a.loop_max_iterations 5

  # Loop termination condition
  a.loop_condition(:done, true)

  # Store final result
  a.output_key :loop_result
end

# Register the loop agent definition
ADK::GlobalDefinitionRegistry.register(loop_agent)

puts "Agent definitions registered. Creating session and agent instances..."

# Create a session service for state management
session_service = ADK::SessionService::InMemory.new
user_id = "demo-user"
app_name = "loop-example"

# Create a session
session = session_service.create_session(
  app_name: app_name,
  user_id: user_id,
  initial_state: { count: 0 }
)
session_id = session.id

puts "Created session with ID: #{session_id}"

# Create agent instances

# 1. Counter Agent implementation
counter_agent_instance = ADK::Agent.new(definition: counter_agent)

# Override execute_plan to implement the counting logic
def counter_agent_instance.execute_plan(plan, session, session_service)
  # Get the session ID from the session object
  session_id = session.id

  # Get current count from session state
  current_count = session_service.get_state(session_id: session_id, key: :count) || 0

  # Increment count
  new_count = current_count + 1

  # Update session state with new count
  session_service.set_state(session_id: session_id, key: :count, value: new_count)

  # Create success result with count info
  result_hash = {
    status: :success,
    result: "Counter incremented to #{new_count}"
  }

  # Return the details and the result in the format expected by the parent method
  { details: [result_hash], last_result: result_hash }
end

# 2. Condition Agent implementation
condition_agent_instance = ADK::Agent.new(definition: condition_agent)

# Override execute_plan to implement the condition check
def condition_agent_instance.execute_plan(plan, session, session_service)
  # Get the session ID from the session object
  session_id = session.id

  # Get current count
  current_count = session_service.get_state(session_id: session_id, key: :count) || 0

  # Check if we've reached our target count (3 for this example)
  target = 3
  done = current_count >= target

  # Set the done flag in session state to control loop termination
  session_service.set_state(session_id: session_id, key: :done, value: done)

  # Create success result
  result_hash = {
    status: :success,
    result: done ? "Target count reached (#{current_count} >= #{target}). Loop should terminate." :
                  "Target count not yet reached (#{current_count} < #{target}). Loop should continue."
  }

  # Return the details and the result in the format expected by the parent method
  { details: [result_hash], last_result: result_hash }
end

# Create the loop agent that will coordinate the whole process
loop_agent_instance = ADK::Agents::LoopAgent.new(
  definition: loop_agent,
  sub_agents: [counter_agent_instance, condition_agent_instance]
)

# Start all agents
puts "Starting agents..."
counter_agent_instance.start
condition_agent_instance.start
loop_agent_instance.start

puts "Starting loop agent execution..."
puts "Loop will continue until count reaches 3 or 5 max iterations..."
puts "------------------------------"

# Execute the loop agent
result = loop_agent_instance.run_task(
  session_id: session_id,
  user_input: "Start counting loop",
  session_service: session_service
)

puts "Loop agent execution complete!"
puts "------------------------------"
puts "Final result: #{result.content[:status]}"
puts "Iterations completed: #{result.content[:iterations_completed] || 'N/A'}"
puts "Loop condition met? #{result.content[:loop_condition_met] || 'N/A'}"
puts

if result.content[:status] == :error
  puts "Error: #{result.content[:error_message]}"
else
  puts "Iteration details:"

  # Print details from each iteration if available
  if result.content[:iterations]
    result.content[:iterations].each_with_index do |iteration, i|
      puts "Iteration #{i + 1}:"

      # Print each sub-agent's results in this iteration
      iteration[:results].each do |sub_result|
        puts "  - #{sub_result[:agent]}: #{sub_result[:result][:result]}"
      end
      puts
    end
  else
    puts "No iteration details available."
  end

  # Check final state values
  final_count = session_service.get_state(session_id: session_id, key: :count)
  puts "Final count in session state: #{final_count}"
  puts "Done flag in session state: #{session_service.get_state(session_id: session_id, key: :done)}"
end

puts "------------------------------"
