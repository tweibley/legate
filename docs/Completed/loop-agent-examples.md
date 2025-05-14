# Using LoopAgent in the ADK

The ADK provides a `LoopAgent` class that allows you to execute a set of sub-agents repeatedly in a loop until either:
- A specified condition is met
- A maximum number of iterations is reached
- An error occurs in one of the sub-agents

This document explains how to use the LoopAgent and provides examples.

## LoopAgent Features

- Execute multiple sub-agents in sequence for each iteration of the loop
- Define a maximum number of iterations as a safety measure
- Set a termination condition based on a value in the session state
- Get detailed results from each iteration
- Store the final result in the session state

## Creating a LoopAgent

To create a LoopAgent, you need to:

1. Define the agent with agent_type set to `:loop`
2. Specify the sub-agents to execute in each iteration
3. Set loop termination conditions (max iterations and/or state-based condition)
4. Create agent instances for each sub-agent and the loop agent
5. Start all agents before execution

### Agent Definition DSL

```ruby
loop_agent = ADK::AgentDefinition.new.define do |a|
  a.name :my_loop_agent
  a.description 'An agent that executes a loop'
  a.instruction 'You run a loop until a condition is met.'
  a.agent_type :loop  # This is required for LoopAgent
  
  # Define sub-agents to run in sequence for each iteration
  a.loop_sub_agents [:agent1, :agent2, :agent3]
  
  # Set maximum iterations (required if no condition)
  a.loop_max_iterations 10
  
  # Set termination condition (required if no max_iterations)
  a.loop_condition(:done_flag, true)
  
  # Optional - store final result in session state
  a.output_key :loop_result
end
```

## Example 1: Simple Counter Loop

This example demonstrates a simple counter that increments until it reaches a target value.

```ruby
# First, define sub-agents that will be used in the loop

# 1. Counter agent - increments a counter in session state
counter_agent = ADK::AgentDefinition.new.define do |a|
  a.name :counter_agent
  a.description 'Increments a counter in session state'
  a.instruction 'You increment a counter and report the new count.'
  a.use_tool :echo
  a.output_key :counter_result
end

# 2. Check condition agent - examines count and decides if we need to continue
condition_agent = ADK::AgentDefinition.new.define do |a|
  a.name :condition_agent
  a.description 'Checks if loop should continue based on count'
  a.instruction 'Check the counter and set done to true if target is reached.'
  a.use_tool :echo
  a.output_key :done
end

# Now define the loop agent that uses the sub-agents
loop_agent = ADK::AgentDefinition.new.define do |a|
  a.name :loop_demo_agent
  a.description 'Demonstrates loop agent functionality'
  a.instruction 'You run a loop that counts until a condition is met.'
  a.agent_type :loop  # This is important - specifies this is a loop agent
  
  # Sub-agents to execute in each loop iteration (in sequence)
  a.loop_sub_agents [:counter_agent, :condition_agent]
  
  # Maximum number of iterations (safety valve)
  a.loop_max_iterations 5
  
  # Loop termination condition
  a.loop_condition(:done, true)
  
  # Store final result
  a.output_key :loop_result
end
```

## Example 2: Text Refinement Loop

This more complex example shows how to use the LoopAgent for iterative refinement of text, with three sub-agents working together:

1. A critic agent that analyzes text and provides feedback with a score
2. An improver agent that enhances the text based on feedback
3. An assessment agent that determines if the refinement is complete

```ruby
# Define the sub-agents for text refinement

# 1. Critique Agent - analyzes text and provides feedback
critic_agent = ADK::AgentDefinition.new.define do |a|
  a.name :critic_agent
  a.description 'Analyzes text and provides critical feedback for improvement'
  a.instruction 'You are a literary critic. Analyze the provided text and give constructive criticism. 
                Score the text from 1-10 where 10 is perfect. Be honest but fair.'
  a.use_tool :echo
  a.output_key :critique_result
end

# 2. Improvement Agent - takes text and critique and improves the text
improver_agent = ADK::AgentDefinition.new.define do |a|
  a.name :improver_agent
  a.description 'Improves text based on critical feedback'
  a.instruction 'You are a skilled writer. Take the existing text and the critique, then produce an improved version.'
  a.use_tool :echo
  a.output_key :improved_text
end

# 3. Assessment Agent - checks if the refinement process is complete
assessment_agent = ADK::AgentDefinition.new.define do |a|
  a.name :assessment_agent
  a.description 'Determines if refinement process is complete'
  a.instruction 'You assess whether the text refinement is complete based on the critique score. 
                 If score is 8 or higher, refinement is complete.'
  a.use_tool :echo
  a.output_key :assessment_result
end

# Define the loop agent to coordinate the process
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
```

## Important Implementation Notes

When implementing custom agent behavior, you need to override the `execute_plan` method with the correct signature:

```ruby
def my_agent_instance.execute_plan(plan, session, session_service)
  # Get session ID from the session object
  session_id = session.id
  
  # Your custom implementation
  # ...
  
  # Create result hash
  result_hash = {
    status: :success,
    result: "Your result here"
  }
  
  # Return in the expected format
  { details: [result_hash], last_result: result_hash }
end
```

Remember to:

1. Extract the session_id from the session object
2. Return the result in the correct format with both details and last_result
3. Start all agents before execution

## Run Loop Execution

To execute a loop agent:

```ruby
# Create the loop agent with its sub-agents
loop_agent_instance = ADK::Agents::LoopAgent.new(
  definition: loop_agent_definition,
  sub_agents: [sub_agent1, sub_agent2, sub_agent3]
)

# Start all agents before execution
sub_agent1.start
sub_agent2.start
sub_agent3.start
loop_agent_instance.start

# Execute the loop
result = loop_agent_instance.run_task(
  session_id: session_id,
  user_input: "User's initial input",
  session_service: session_service
)

# The result contains:
# - status: :success or :error
# - iterations_completed: Number of iterations completed
# - loop_condition_met: Whether the loop condition was met
# - iterations: Detailed results from each iteration
```

## Common Use Cases for LoopAgent

1. **Iterative Refinement**: Progressively improve content through multiple passes
2. **Recursive Problem Solving**: Break down complex problems and solve them step by step
3. **Polling and Monitoring**: Repeatedly check for a condition until it's satisfied
4. **Multi-Step Data Processing**: Process data through a sequence of transformations until complete
5. **Conversational Agents**: Implement dynamic multi-turn conversations with state

## Full Examples

You can find complete working examples in the examples directory:
- `examples/loop_agent_example.rb`: Basic counting example
- `examples/task_refinement_loop_agent.rb`: Text refinement example 