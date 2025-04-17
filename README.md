# ADK Ruby

**Author:** Taylor Weibley  
**Repository:** [https://github.com/tweibley/adk-ruby](https://github.com/tweibley/adk-ruby)

ADK (Agent Development Kit) for Ruby is a framework for building AI agents with dynamic tool selection, multi-step planning, and session management.

## Features

- **Flexible Agent Architecture**: Create agents with custom tools, models, and capabilities
- **Dynamic Tool System**: Register and use tools with automatic parameter validation
- **LLM-Powered Multi-Step Planning**: Agents can break down complex tasks into steps
- **Session Management**: Track and manage agent interactions with persistent sessions
- **Command Line Interface**: Easy-to-use CLI for running agents and web UI
- **Web UI**: Visual interface for agent interaction and monitoring
- **Event-Based Communication**: Structured events for agent responses and errors
- **Comprehensive Logging**: Detailed logging of agent operations and planning

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'adk'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install adk
```

## Configuration

### Environment Variables

- `RACK_ENV`: Set to `development` or `production` (default: `development`)
- `GOOGLE_API_KEY`: Your Google API key for the planner (required)
- `ADK_LOG_LEVEL`: Logging level (default: `INFO`, options: `DEBUG`, `INFO`, `WARN`, `ERROR`)
- `ADK_REDIS_URL`: Redis connection URL (default: `redis://localhost:6379/0`)

### Redis Setup

ADK uses Redis for session persistence. Ensure Redis is running:

```bash
# macOS (via Homebrew)
brew services start redis

# Linux
sudo service redis-server start
```

## Quick Start

1. **Create a `.env` file:**
   ```
   RACK_ENV=development
   GOOGLE_API_KEY=your_api_key_here
   ADK_LOG_LEVEL=DEBUG  # Optional, for detailed logging
   ```

2. **Start the Web UI:**
   ```bash
   adk web start
   ```

3. **Access the Web Interface:**
   Open your browser to `http://localhost:4567`

## Examples

ADK comes with several examples demonstrating different capabilities:

### 1. Simple Echo Agent (`examples/simple_agent.rb`)
A basic example showing session-based agent interaction:
```ruby
# Create and configure agent
agent = ADK::Agent.new(
  name: 'simple_echo_agent',
  description: 'A simple agent that can echo messages'
)
agent.add_tool(ADK::ToolRegistry.create_instance(:echo))

# Create session
session_service = ADK::SessionService::InMemory.new
session = session_service.create_session(app_name: agent.name, user_id: 'example_user')

# Run task
result = agent.run_task(
  session_id: session.id,
  user_input: 'Hello, world!',
  session_service: session_service
)
```

### 2. Random Calculator (`examples/random_calculator.rb`)
Demonstrates multi-step planning with multiple tools:
```ruby
# Create agent with multiple tools
agent = ADK::Agent.new(
  name: 'multi_step_hash_agent_001',
  description: 'An agent that uses multiple tools and returns structured results.'
)
agent.add_tool(ADK::ToolRegistry.create_instance(:random_number))
agent.add_tool(ADK::ToolRegistry.create_instance(:calculator))

# Run complex task
result = agent.run_task(
  session_id: session.id,
  user_input: 'Get a random number between 10 and 20, then multiply it by 3.',
  session_service: session_service
)
```

### 3. Multi-Tool Agent (`examples/multi_tool_agent.rb`)
Showcases all available tools and task delegation:
```ruby
# Create agent with all tools
agent = ADK::Agent.new(
  name: 'multi_tool_agent',
  description: 'An agent that can use multiple tools including echo, calculator, cat facts, random numbers, and task delegation'
)

# Add all available tools
tools = [
  :echo, :calculator, :cat_facts, :random_number, :delegate_task
].map { |tool| ADK::ToolRegistry.create_instance(tool) }
tools.each { |tool| agent.add_tool(tool) }

# Run various tasks
tasks = [
  "Echo this message: Hello from multi-tool agent!",
  "Calculate 15 * 7",
  "Get me a cat fact",
  "Generate a random number between 1 and 10",
  "Delegate this task to calculator_agent: what is 20 / 4"
]
tasks.each do |task|
  result = agent.run_task(
    session_id: session.id,
    user_input: task,
    session_service: session_service
  )
end
```

## Core Concepts

### Agents

Agents are the core components that can:
- Use tools to perform tasks
- Maintain state through sessions
- Plan multi-step operations
- Handle errors gracefully

```ruby
agent = ADK::Agent.new(
  name: 'my_agent',
  description: 'Description of what the agent does'
)
```

### Tools

Tools are modular components that agents can use:
- **Echo**: Simple message echoing
- **Calculator**: Basic arithmetic operations
- **CatFacts**: Retrieve random cat facts
- **RandomNumber**: Generate random numbers
- **AgentTool**: Delegate tasks to other agents

```ruby
# Register a tool
tool = ADK::ToolRegistry.create_instance(:calculator)
agent.add_tool(tool)
```

### Sessions

Sessions track agent interactions and maintain state:
```ruby
session_service = ADK::SessionService::InMemory.new
session = session_service.create_session(
  app_name: agent.name,
  user_id: 'user123'
)
```

### Events

Events provide structured communication:
```ruby
# Success event
ADK::Event.new(
  role: :assistant,
  content: { status: :success, result: 'Task completed' }
)

# Error event
ADK::Event.new(
  role: :assistant,
  content: { status: :error, error_message: 'Something went wrong' }
)
```

## Development

After checking out the repo:

1. **Install Dependencies:**
   ```bash
   bundle install
   ```

2. **Setup Environment:**
   - Ensure Redis is running
   - Create a `.env` file with required variables
   - Set `ADK_LOG_LEVEL=DEBUG` for detailed logging

3. **Run Tests:**
   ```bash
   bundle exec rake spec     # Run RSpec tests
   bundle exec rake rubocop  # Run Rubocop linting
   bundle exec rake yard     # Generate YARD documentation
   ```

4. **Run Examples:**
   ```bash
   ruby examples/simple_agent.rb
   ruby examples/random_calculator.rb
   ruby examples/multi_tool_agent.rb
   ```

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/tweibley/adk-ruby](https://github.com/tweibley/adk-ruby).

## License

If you are DHH or work at Basecamp/37signals you absolutely cannot use this.