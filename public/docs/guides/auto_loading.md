# Auto-Loading Custom Tools and Agents

This guide explains how Legate automatically discovers and loads your custom tools and agent definitions when starting the web server.

## Overview

When you run `legate web start`, Legate automatically scans conventional directories for Ruby files containing custom tools and agents. This means you can:

- Drop a tool file in `lib/tools/` and it's automatically available
- Drop an agent file in `lib/agents/` and it appears in the Web UI
- No manual configuration required

> The Web UI [AI builders](ai_code_generators) write to `tools/` and `agents/` for
> you (when installing a tool live, or via an agent's **Save to `agents/`** action),
> so those generated files are picked up here on the next start too.

## Directory Structure

Legate scans the following directories relative to where you run `legate web start`:

### For Tools

```
./lib/tools/           # Primary location
./agents/lib/tools/    # Alternative (nested project)
./tools/               # Simple projects
```

### For Agents

```
./lib/agents/          # Primary location
./agents/lib/agents/   # Alternative (nested project)
./agents/              # Simple projects (excludes /tools/ subdirs)
```

### Recommended Structure

```
your_project/
├── Gemfile
├── .env                    # Environment variables (GOOGLE_API_KEY, etc.)
├── lib/
│   ├── tools/
│   │   ├── weather_tool.rb
│   │   ├── email_validator_tool.rb
│   │   └── custom_api_tool.rb
│   └── agents/
│       ├── customer_support_agent.rb
│       ├── data_processor_agent.rb
│       └── notification_agent.rb
└── legate_init.rb            # Optional: custom initialization
```

## Creating Auto-Loadable Tools

Your tool file should:

1. Define the tool class
2. Register it with `GlobalToolManager`

**Example: `lib/tools/greeting_tool.rb`**

```ruby
# frozen_string_literal: true

require 'legate/tool'

class GreetingTool < Legate::Tool
  tool_description 'Generates a personalized greeting'
  
  parameter :name,
    type: :string,
    description: 'Name of the person to greet',
    required: true
    
  parameter :style,
    type: :string,
    description: 'Greeting style: formal, casual, or enthusiastic',
    required: false
  
  private
  
  def perform_execution(params, context)
    name = params[:name]
    style = params[:style] || 'casual'
    
    greeting = case style
    when 'formal'
      "Good day, #{name}. How may I assist you?"
    when 'enthusiastic'
      "Hey #{name}! Great to see you! 🎉"
    else
      "Hello, #{name}!"
    end
    
    { status: :success, result: greeting }
  end
end

# This line makes the tool available to agents
Legate::GlobalToolManager.register_tool(GreetingTool)
```

## Creating Auto-Loadable Agents

Your agent file should:

1. Define the agent using `AgentDefinition`
2. Register it with `GlobalDefinitionRegistry`

**Example: `lib/agents/greeter_agent.rb`**

```ruby
# frozen_string_literal: true

require 'legate'

definition = Legate::AgentDefinition.new.define do |a|
  a.name :greeter
  a.description 'A friendly agent that greets users'
  
  a.instruction <<~INSTRUCTION
    You are a friendly greeter agent.
    
    When a user introduces themselves or asks for a greeting,
    use the greeting_tool to generate an appropriate response.
    
    Match the greeting style to the user's tone:
    - Formal requests get formal greetings
    - Casual messages get casual greetings
    - Excited users get enthusiastic greetings
  INSTRUCTION
  
  a.use_tool :greeting_tool
  a.model_name 'gemini-2.0-flash'
  a.temperature 0.7
end

# This line makes the agent appear in the Web UI
Legate::GlobalDefinitionRegistry.register(definition)
```

## Load Order

Legate loads files in this order:

1. **Initializer** (if present) - `legate_init.rb`, `config/legate_init.rb`, or `agents/legate_init.rb`
2. **Tools** - All `.rb` files in tool directories
3. **Agents** - All `.rb` files in agent directories
4. **Register Definitions** - Agents are registered in the `GlobalDefinitionRegistry` for the Web UI

This order ensures tools are available before agents that reference them.

## Custom Initializer

For advanced setup, create a `legate_init.rb` file in your project root:

```ruby
# legate_init.rb

# Set up environment
ENV['MY_CUSTOM_VAR'] ||= 'default_value'

# Configure Legate
Legate.configure do |config|
  config.default_model_name = 'gemini-2.0-flash'
  config.default_temperature = 0.5
end

# Pre-load specific dependencies
require 'some_custom_gem'

# Log that initialization completed
Legate.logger.info "Custom initialization complete"
```

The initializer runs before auto-loading, so you can set up anything your tools/agents need.

## Startup Logs

When auto-loading works correctly, you'll see log messages like:

```
INFO: Auto-loaded 3 custom tool file(s). Registered tools: [:echo, :calculator, ..., :greeting_tool, :weather_tool, :email_validator_tool]
INFO: Auto-loaded 2 custom agent file(s). Registered agents: [:greeter, :data_processor]
INFO: Synced agent 'greeter' to definition store for Web UI
INFO: Synced agent 'data_processor' to definition store for Web UI
```

## Disabling Auto-Loading

If you need to disable auto-loading (e.g., for testing):

```bash
bundle exec legate web start --no-autoload
```

## Excluding Files

The auto-loader automatically skips:

- Test files (`*_spec.rb`, `*_test.rb`)
- Files in `/tools/` subdirectories when loading agents (to avoid double-loading)

## Common Issues

### Tool Not Appearing

1. **Check the file location** - Must be in one of the scanned directories
2. **Check registration** - File must call `Legate::GlobalToolManager.register_tool(YourTool)`
3. **Check for errors** - Look at startup logs for load failures

### Agent Not Appearing in Web UI

1. **Check registration** - File must call `Legate::GlobalDefinitionRegistry.register(definition)`
2. **Don't run the agent** - The file should only define and register, not execute
3. **Check registration** - Agents must be registered in `GlobalDefinitionRegistry`

### Load Errors

If a file fails to load, you'll see:

```
WARN: Failed to load tool file /path/to/file.rb: SomeError - error message
```

Check the file for syntax errors or missing dependencies.

### Wrong require_relative Paths

**Don't use `require_relative` for other auto-loaded files.** Since tools load before agents, your agent can reference tools by symbol name without requiring them:

```ruby
# DON'T do this:
require_relative '../tools/my_tool'  # Wrong!

# DO this:
a.use_tool :my_tool  # The tool is already loaded
```

## Running from Different Directories

The auto-loader scans relative to the current working directory. Always run `legate web start` from your project root:

```bash
cd /path/to/your/project
bundle exec legate web start
```

## Example Project

Here's a complete example project structure:

```
my_legate_project/
├── Gemfile
│   # source 'https://rubygems.org'
│   # gem 'legate'
│
├── .env
│   # GOOGLE_API_KEY=your_api_key_here
│
├── lib/
│   ├── tools/
│   │   └── math_helper_tool.rb
│   └── agents/
│       └── math_tutor_agent.rb
│
└── README.md
```

**`lib/tools/math_helper_tool.rb`:**
```ruby
require 'legate/tool'

class MathHelperTool < Legate::Tool
  tool_description 'Explains math concepts step by step'
  
  parameter :problem, type: :string, required: true,
    description: 'The math problem or concept to explain'
  
  private
  
  def perform_execution(params, context)
    { status: :success, result: "Let me explain: #{params[:problem]}" }
  end
end

Legate::GlobalToolManager.register_tool(MathHelperTool)
```

**`lib/agents/math_tutor_agent.rb`:**
```ruby
require 'legate'

definition = Legate::AgentDefinition.new.define do |a|
  a.name :math_tutor
  a.description 'A patient math tutor that explains concepts'
  a.instruction 'You are a patient math tutor. Use the math_helper_tool to explain concepts.'
  a.use_tool :math_helper_tool
  a.use_tool :calculator
  a.model_name 'gemini-2.0-flash'
end

Legate::GlobalDefinitionRegistry.register(definition)
```

**Start the server:**
```bash
cd my_legate_project
bundle install
bundle exec legate web start
```

Your math tutor agent will automatically appear in the Web UI!

## Related Documentation

- [AI Code Generators](ai_code_generators) - Generate tools and agents with AI
- [Built-in Tools](../tools/legate_built_in_tools) - Available built-in tools
- [Agent Lifecycle](../core_concepts/legate_agent_lifecycle) - How agents work




