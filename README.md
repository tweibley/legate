# ADK Ruby

Agent Development Kit (ADK) for Ruby is a framework for building and managing AI agents. It provides a robust foundation for creating intelligent agents that can perform complex tasks, maintain state, and interact with various tools and services.

## Features

- Flexible agent architecture
- Built-in memory management
- Extensible tool system
- Session management
- Task planning capabilities
- Event handling system
- Telemetry and monitoring
- Web UI with modern styling

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'adk-ruby'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install adk-ruby
```

## Usage

### Ruby API

```ruby
#!/usr/bin/env ruby

require 'bundler/setup'
require 'adk'

# Create a new agent
agent = ADK::Agent.new(
  name: 'my_agent',
  description: 'A sample agent'
)

# Add tools to the agent
agent.add_tool(ADK::Tools::Echo.new)

# Start the agent
agent.start

# Execute a task
puts agent.run_task('Tell me a cat fact!')

```

### Command Line Interface

```bash
# View ADK version
adk version

# Agent commands
adk agent create my_agent --description="My test agent"
adk agent list
adk agent start my_agent
adk agent execute my_agent "Hello, world!"
adk agent stop my_agent

# Tool commands
adk tool list
adk tool info echo
adk tool execute echo "Hello from the echo tool!"

# Compile Sass files
adk compile-sass
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

### Sass Compilation

The web UI uses Sass for styling. To compile Sass files, you can use one of the following methods:

1. Run the Rake task:
   ```bash
   rake sass
   ```

2. Use the compile-sass script:
   ```bash
   bin/compile-sass
   ```

3. Sass files are automatically compiled when the web application starts.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/yourusername/adk-ruby.

## License

The gem is available as open source under the terms of the Apache License 2.0. 