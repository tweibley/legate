# frozen_string_literal: true

# This example demonstrates a practical use of LoopAgent for iterative refinement of text
# Using two LLM agents in a loop - one to critique and another to improve based on the critique

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'adk'
require 'adk/agents/loop_agent'

# Create a session service for state management
session_service = ADK::SessionService::InMemory.new
user_id = "demo-user"
app_name = "loop-example"

# Create a session with initial state
initial_text = "The cat sat on the mat."
session = session_service.create_session(
  app_name: app_name,
  user_id: user_id,
  initial_state: {
    current_text: initial_text,
    refinement_done: false,
    refinement_score: 0
  }
)
session_id = session.id

puts "Created session with ID: #{session_id}"
puts "Initial text: #{initial_text}"
puts "Refinement process will loop until score reaches 8 or max 5 iterations"
puts "------------------------------"

# 1. Critique Agent - analyzes text and provides feedback
critic_agent = ADK::AgentDefinition.new.define do |a|
  a.name :critic_agent
  a.description 'Analyzes text and provides critical feedback for improvement'
  a.instruction 'You are a literary critic. Analyze the provided text and give constructive criticism.
                Score the text from 1-10 where 10 is perfect. Be honest but fair.'
  a.use_tool :echo
  a.output_key :critique_result
end
ADK::GlobalDefinitionRegistry.register(critic_agent)

# 2. Improvement Agent - takes text and critique and improves the text
improver_agent = ADK::AgentDefinition.new.define do |a|
  a.name :improver_agent
  a.description 'Improves text based on critical feedback'
  a.instruction 'You are a skilled writer. Take the existing text and the critique, then produce an improved version.'
  a.use_tool :echo
  a.output_key :improved_text
end
ADK::GlobalDefinitionRegistry.register(improver_agent)

# 3. Assessment Agent - checks if the refinement process is complete
assessment_agent = ADK::AgentDefinition.new.define do |a|
  a.name :assessment_agent
  a.description 'Determines if refinement process is complete'
  a.instruction 'You assess whether the text refinement is complete based on the critique score.
                 If score is 8 or higher, refinement is complete.'
  a.use_tool :echo
  a.output_key :assessment_result
end
ADK::GlobalDefinitionRegistry.register(assessment_agent)

# Finally, define the loop agent to coordinate the refinement process
refinement_loop = ADK::AgentDefinition.new.define do |a|
  a.name :text_refinement_agent
  a.description 'Coordinates the text refinement process through multiple iterations'
  a.instruction 'You coordinate a process of iterative text refinement.'
  a.agent_type :loop

  # Define the sub-agents to run in each iteration
  a.loop_sub_agents [:critic_agent, :improver_agent, :assessment_agent]

  # Set loop termination conditions
  a.loop_max_iterations 5
  a.loop_condition(:refinement_done, true)

  # Store the final result
  a.output_key :refinement_result
end
ADK::GlobalDefinitionRegistry.register(refinement_loop)

# Create the agent instances and customize their behaviors

# 1. Critic Agent Implementation
critic_instance = ADK::Agent.new(definition: critic_agent)
def critic_instance.execute_plan(plan, session, session_service)
  # Get the session ID from the session object
  session_id = session.id

  # Get the current text
  current_text = session_service.get_state(session_id: session_id, key: :current_text)

  # Generate critique (in a real agent, this would use an LLM)
  iteration = session_service.get_state(session_id: session_id, key: :count) || 0

  # For this demo, we'll simulate different scores at each iteration
  score = [3, 5, 7, 9, 10].at(iteration) || 10

  # Store the score in state for the assessment agent
  session_service.set_state(session_id: session_id, key: :refinement_score, value: score)

  critique = if score < 5
               "Basic text with simple structure. Score: #{score}/10. Needs more descriptive language and complexity."
             elsif score < 8
               "Good progress, but could use more creativity. Score: #{score}/10. Consider adding more vivid imagery."
             else
               "Excellent work, very polished. Score: #{score}/10. Minor refinements could still be made."
             end

  critique_result = {
    text: current_text,
    critique: critique,
    score: score
  }

  # Store the critique for other agents to use
  session_service.set_state(session_id: session_id, key: :current_critique, value: critique_result)

  # Create success result
  result_hash = {
    status: :success,
    result: critique,
    score: score
  }

  # Return the details and the result in the format expected by the parent method
  { details: [result_hash], last_result: result_hash }
end

# 2. Improver Agent Implementation
improver_instance = ADK::Agent.new(definition: improver_agent)
def improver_instance.execute_plan(plan, session, session_service)
  # Get the session ID from the session object
  session_id = session.id

  # Get the current text and critique
  current_text = session_service.get_state(session_id: session_id, key: :current_text)
  critique_result = session_service.get_state(session_id: session_id, key: :current_critique)

  # Keep track of iterations to simulate improvement
  iteration = session_service.get_state(session_id: session_id, key: :count) || 0
  iteration += 1
  session_service.set_state(session_id: session_id, key: :count, value: iteration)

  # Generate improved text (in a real agent, this would use an LLM)
  improved_text = case iteration
                  when 1
                    "The sleepy cat curled up on the worn mat."
                  when 2
                    "The orange tabby cat stretched lazily before settling on the woven mat by the fireplace."
                  when 3
                    "Basking in the afternoon sunlight, the orange tabby cat stretched lazily before settling on the intricately woven mat by the crackling fireplace."
                  when 4
                    "Basking in the warm afternoon sunlight that streamed through the window, the orange tabby cat stretched lazily, arching its back, before settling comfortably on the intricately woven mat by the crackling fireplace."
                  else
                    "Basking in the warm golden rays of the afternoon sunlight that streamed through the dusty bay window, the elderly orange tabby cat stretched lazily, arching its back with practiced grace, before settling comfortably on the intricately woven Persian mat positioned strategically by the crackling oak-wood fireplace."
                  end

  # Store the improved text for next iteration
  session_service.set_state(session_id: session_id, key: :current_text, value: improved_text)

  # Create success result
  result_hash = {
    status: :success,
    result: "Improved text based on critique (score: #{critique_result[:score]}/10):\n#{improved_text}"
  }

  # Return the details and the result in the format expected by the parent method
  { details: [result_hash], last_result: result_hash }
end

# 3. Assessment Agent Implementation
assessment_instance = ADK::Agent.new(definition: assessment_agent)
def assessment_instance.execute_plan(plan, session, session_service)
  # Get the session ID from the session object
  session_id = session.id

  # Get the current score
  score = session_service.get_state(session_id: session_id, key: :refinement_score)

  # Determine if we're done (score >= 8)
  done = score >= 8

  # Set the done flag to control loop termination
  session_service.set_state(session_id: session_id, key: :refinement_done, value: done)

  # Create success result
  result_hash = {
    status: :success,
    result: done ? "Refinement complete! Final score: #{score}/10" :
                  "Refinement should continue. Current score: #{score}/10"
  }

  # Return the details and the result in the format expected by the parent method
  { details: [result_hash], last_result: result_hash }
end

# Create the loop agent to orchestrate the process
loop_agent_instance = ADK::Agents::LoopAgent.new(
  definition: refinement_loop,
  sub_agents: [critic_instance, improver_instance, assessment_instance]
)

# Start all agents
puts "Starting agents..."
critic_instance.start
improver_instance.start
assessment_instance.start
loop_agent_instance.start

# Run the refinement loop
puts "Starting text refinement process..."
puts "------------------------------"

result = loop_agent_instance.run_task(
  session_id: session_id,
  user_input: "Please refine this text: #{initial_text}",
  session_service: session_service
)

puts "Text refinement process complete!"
puts "------------------------------"
puts "Final result: #{result.content[:status]}"
puts "Iterations completed: #{result.content[:iterations_completed] || 'N/A'}"
puts "Loop condition met? #{result.content[:loop_condition_met] || 'N/A'}"
puts

if result.content[:status] == :error
  puts "Error: #{result.content[:error_message]}"
  puts "------------------------------"
  exit 1
end

# Print a summary of the refinement process
puts "Refinement process summary:"
puts "------------------------------"
puts "Initial text: #{initial_text}"
puts

if result.content[:iterations]
  result.content[:iterations].each_with_index do |iteration, i|
    puts "ITERATION #{i + 1}:"

    # Extract and show results from each sub-agent
    critic_result = iteration[:results].find { |r| r[:agent] == :critic_agent }
    improver_result = iteration[:results].find { |r| r[:agent] == :improver_agent }
    assessment_result = iteration[:results].find { |r| r[:agent] == :assessment_agent }

    if critic_result && improver_result && assessment_result
      puts "Critique: #{critic_result[:result][:result]}"
      puts "Score: #{critic_result[:result][:score]}/10"
      puts "Improvement: #{improver_result[:result][:result]}"
      puts "Assessment: #{assessment_result[:result][:result]}"
    else
      puts "Incomplete iteration data"
    end
    puts
  end
else
  puts "No iteration details available."
end

# Show final refined text
final_text = session_service.get_state(session_id: session_id, key: :current_text)
puts "FINAL REFINED TEXT:"
puts final_text
puts "------------------------------"
