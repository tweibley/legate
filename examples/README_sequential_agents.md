# Sequential Agents in Legate

Sequential agents are a powerful feature in Legate that allow you to compose multiple specialized agents into a workflow where agents are executed in a predetermined sequence. This approach lets you break down complex tasks into smaller, more manageable components that work together.

## How Sequential Agents Work

1. **Agent Composition**: A sequential agent is composed of multiple sub-agents, each with its own specialized task.
2. **Ordered Execution**: Sub-agents are executed in a predefined order, with each agent performing its task before passing control to the next agent.
3. **State Management**: Each sub-agent can store its results in the session state using the `output_key` attribute, making results available to later sub-agents.
4. **Coordinated Workflow**: The sequential agent orchestrates the entire process, handling failures and collecting results from each step.

## Travel Planner Examples

The Legate provides two different implementations of a travel planner using sequential agents, demonstrating different approaches to agent orchestration:

### 1. Automatic Sequential Execution (`travel_planner_auto_sequential.rb`)

This example demonstrates how to use the built-in `SequentialAgent` class to automatically handle the execution flow:

```bash
bundle exec ruby examples/advanced/workflows/travel_planner_auto_sequential.rb
```

Key features:
- The `SequentialAgent` automatically runs all sub-agents in the defined order
- Each agent stores its output in session state using `output_key`
- Subsequent agents can access previous agents' outputs from the session state
- Visualizes progress with `tty-spinner`

### 2. Custom Sequential Execution (`travel_planner_sequential.rb`)

This example demonstrates a custom wrapper around `SequentialAgent` for more explicit control:

```bash
bundle exec ruby examples/advanced/workflows/travel_planner_sequential.rb
```

Key features:
- Uses a custom wrapper class to enhance inputs for each agent
- Shows how to explicitly pass data between agents
- Provides more control over the execution flow
- Demonstrates both automatic and custom orchestration approaches

### Sub-Agents in the Travel Planner:

Both examples use the same set of specialized agents:

1. **Destination Research Agent**: Analyzes user preferences and suggests suitable destinations
   - Stores results with `output_key: :destination_results`

2. **Itinerary Planner Agent**: Creates a daily itinerary for the chosen destination
   - Stores results with `output_key: :itinerary_results`

3. **Budget Estimator Agent**: Calculates costs for the planned trip
   - Stores results with `output_key: :budget_results`

4. **Trip Summarizer Agent**: Creates a final summary combining all information
   - Stores results with `output_key: :trip_summary`

### Main Sequential Agent:

The main agent coordinates all sub-agents by:
- Setting `agent_type: :sequential` to specify it's a sequential workflow
- Defining the execution order with `sequential_sub_agents [:destination_research, :itinerary_planner, :budget_estimator, :trip_summarizer]`
- Storing the final result with `output_key: :complete_travel_plan`

## Data Flow Between Agents

Sequential agents share data through session state:

1. Each sub-agent stores its output in session state using its designated `output_key`
2. Subsequent agents can retrieve this data using `session_service.get_state(session_id: session_id, key: key_name)`
3. This creates a data pipeline where each agent builds upon the work of previous agents

## Key Concepts Demonstrated

- **Agent Composition**: Building complex workflows from simple agents
- **State Management**: Using `output_key` to pass information between agents
- **Error Handling**: Properly handling failures in any step of the sequence
- **Agent Types**: Using the `:sequential` agent type for workflow definition
- **Orchestration Approaches**: Both automatic and custom orchestration methods

## Implementation Approaches

### Automatic Sequential Execution

The simplest approach where the `SequentialAgent` class handles everything:

```ruby
# Parent Sequential Agent Definition
travel_planner_def = Legate::AgentDefinition.new.define do |a|
  a.name :travel_planner
  a.description 'Orchestrates the complete travel planning process'
  a.instruction 'You coordinate the travel planning process'
  a.agent_type :sequential  # This tells Legate to use SequentialAgent
  a.sequential_sub_agents :destination_research, :itinerary_planner, :budget_estimator, :trip_summarizer
  a.output_key :complete_travel_plan
end

# Create and run
travel_planner = Legate::Agents::SequentialAgent.new(
  definition: travel_planner_def,
  sub_agents: [destination_agent, itinerary_agent, budget_agent, summary_agent]
)

result = travel_planner.run_task(
  session_id: session_id,
  user_input: user_input,
  session_service: session_service
)
```

### Custom Sequential Execution

For more control, you can create a wrapper class:

```ruby
class CustomSequentialAgent
  def initialize(sequential_agent)
    @sequential_agent = sequential_agent
    @sub_agents = sequential_agent.instance_variable_get(:@sub_agents)
  end

  def run_task(session_id:, user_input:, session_service:)
    # Run first sub-agent
    result1 = @sub_agents[0].run_task(...)
    
    # Get data from first agent and enhance input for second agent
    data1 = session_service.get_state(session_id: session_id, key: :first_agent_output_key)
    enhanced_input = "#{user_input}\n\nPrevious output: #{data1['result']}"
    
    # Run second sub-agent with enhanced input
    result2 = @sub_agents[1].run_task(
      session_id: session_id,
      user_input: enhanced_input,
      session_service: session_service
    )
    
    # Continue for remaining agents...
  end
end
```

## Creating Your Own Sequential Agents

To create your own sequential agent:

1. Define your sub-agent definitions with appropriate specializations
2. Register all sub-agent definitions with `Legate::GlobalDefinitionRegistry`
3. Define your main sequential agent with:
   ```ruby
   sequential_agent = Legate::AgentDefinition.new.define do |a|
     a.name :your_sequential_agent
     a.description 'Description of your workflow'
     a.instruction 'Instructions for the sequential agent'
     a.agent_type :sequential
     a.sequential_sub_agents [:sub_agent1, :sub_agent2, :sub_agent3]
     a.output_key :final_result_key
   end
   ```
4. Create instances of all sub-agents
5. Create the sequential agent instance, passing it all sub-agent instances
6. Start all agents with `agent.start()`
7. Call `run_task` on the sequential agent 