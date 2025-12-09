# AI-Powered Code Generators

This guide explains how to use the AI-powered code generators in the ADK Web UI to quickly create agents and tools from natural language descriptions.

## Overview

ADK includes two AI-powered generators that use Google's Gemini AI to create production-ready Ruby code:

1. **Agent Generator** - Creates complete `AgentDefinition` code for any type of agent
2. **Tool Generator** - Creates complete `Tool` class code with proper DSL and patterns

Both generators are accessible from the Web UI and produce downloadable Ruby files that you can integrate into your projects.

## Agent Generator

### Accessing the Generator

1. Navigate to the **Agents** page (`/agents`)
2. Click the **"Generate with AI"** button
3. A modal dialog will open with an input form

### Describing Your Agent

Enter a natural language description of the agent you want to create. The AI understands:

- **Basic LLM agents**: "Create an agent that helps users with customer support questions"
- **Workflow agents**: "Create a sequential workflow that first researches a topic, then summarizes the findings"
- **Webhook-enabled agents**: "Create an agent triggered by GitHub webhooks that processes pull request events"
- **Agents with specific tools**: "Create an agent that can perform calculations and look up cat facts"

### Example Descriptions

```
Create an agent that helps users analyze CSV data files and 
generate summary reports.
```

```
Create a sequential workflow agent that:
1. First fetches data from an API
2. Then processes and transforms the data
3. Finally sends a notification with the results
```

```
Create a webhook-enabled agent that receives Stripe payment 
events and updates customer records.
```

### Generated Code Structure

The generator produces complete Ruby code including:

```ruby
# frozen_string_literal: true

require 'adk'

definition = ADK::AgentDefinition.new.define do |a|
  a.name :my_agent
  a.description 'Agent description'
  
  a.instruction <<~INSTRUCTION
    Detailed system prompt...
  INSTRUCTION
  
  # Tools configuration
  a.use_tool :calculator
  a.use_tool :echo
  
  # Model configuration
  a.model_name 'gemini-2.0-flash'
  a.temperature 0.7
end

ADK::GlobalDefinitionRegistry.register(definition)
```

### Supported Agent Types

The generator can create:

| Type | Description | Key DSL Methods |
|------|-------------|-----------------|
| **LLM Agent** | Standard AI agent with tools | `use_tool`, `model_name`, `temperature` |
| **Sequential Agent** | Runs sub-agents in order | `agent_type :sequential`, `sequential_sub_agent_names` |
| **Parallel Agent** | Runs sub-agents concurrently | `agent_type :parallel`, `parallel_sub_agent_names` |
| **Loop Agent** | Repeats until condition met | `agent_type :loop`, `loop_max_iterations`, `loop_condition_*` |
| **Webhook Agent** | Triggered by HTTP webhooks | `webhook_enabled`, `webhook_transformer`, `webhook_validator` |

### Available Tools

The generator knows about all tools registered in your ADK installation. It will only use tools that actually exist and will provide helpful comments if requested functionality requires tools that aren't available.

## Tool Generator

### Accessing the Generator

1. Navigate to the **Tools** page (`/tools`)
2. Click the **"Generate with AI"** button
3. A modal dialog will open with an input form

### Describing Your Tool

Describe what you want the tool to do. The AI will automatically determine the best tool type:

- **Simple Tool**: Local computations, data transformations
- **HTTP API Tool**: External API calls with proper error handling
- **Async Tool**: Long-running background jobs via Sidekiq

### Example Descriptions

**Simple Tool:**
```
Create a tool that converts temperatures between Celsius, 
Fahrenheit, and Kelvin.
```

**HTTP API Tool:**
```
Create a tool that fetches weather data from OpenWeather API 
for a given city name.
```

**Async Tool:**
```
Create a tool that processes large CSV files in the background 
and returns a job ID for status checking.
```

### Generated Code Structure

#### Simple Tool

```ruby
# frozen_string_literal: true

require 'adk/tool'

class TemperatureConverter < ADK::Tool
  tool_description 'Converts temperatures between units'
  
  parameter :value,
    type: :number,
    description: 'Temperature value to convert',
    required: true
    
  parameter :from_unit,
    type: :string,
    description: 'Source unit (celsius, fahrenheit, kelvin)',
    required: true
    
  parameter :to_unit,
    type: :string,
    description: 'Target unit (celsius, fahrenheit, kelvin)',
    required: true
  
  private
  
  def perform_execution(params, context)
    # Conversion logic...
    { status: :success, result: converted_value }
  rescue StandardError => e
    { status: :error, error_message: e.message }
  end
end

ADK::GlobalToolManager.register_tool(TemperatureConverter)
```

#### HTTP API Tool

```ruby
# frozen_string_literal: true

require 'adk/tool'
require 'adk/tools/base/http_client'

class WeatherTool < ADK::Tool
  include ADK::Tools::Base::HttpClient
  
  tool_description 'Fetches weather data from OpenWeather API'
  
  parameter :city,
    type: :string,
    description: 'City name',
    required: true
  
  def initialize(**options)
    super
    setup_http_client(
      base_url: 'https://api.openweathermap.org/data/2.5/',
      headers: { 'Accept' => 'application/json' }
    )
  end
  
  private
  
  def perform_execution(params, context)
    api_key = ENV['OPENWEATHER_API_KEY']
    response = http_get('weather', query: { 
      q: params[:city], 
      appid: api_key 
    })
    
    data = JSON.parse(response.body)
    { status: :success, result: data }
  rescue ADK::ToolHttpError => e
    { status: :error, error_message: "API error: #{e.message}" }
  end
end

ADK::GlobalToolManager.register_tool(WeatherTool)
```

#### Async Tool

```ruby
# frozen_string_literal: true

require 'adk/tools/base_async_job_tool'
require 'sidekiq'

class FileProcessorWorker
  include Sidekiq::Worker
  
  def perform(session_id, file_path)
    jid = self.jid
    ADK::Tools::BaseAsyncJobTool.store_job_pending(jid)
    
    # Process the file...
    result = process_file(file_path)
    
    ADK::Tools::BaseAsyncJobTool.store_job_result(jid, result)
  rescue StandardError => e
    ADK::Tools::BaseAsyncJobTool.store_job_error(jid, e.message, e.class.name)
    raise
  end
end

class FileProcessorTool < ADK::Tools::BaseAsyncJobTool
  tool_description 'Processes large files in the background'
  
  parameter :file_path,
    type: :string,
    description: 'Path to the file to process',
    required: true
  
  def sidekiq_worker_class
    FileProcessorWorker
  end
  
  def prepare_job_arguments(params, context)
    [context.session_id, params[:file_path]]
  end
end

ADK::GlobalToolManager.register_tool(FileProcessorTool)
```

## Using Generated Code

### Export Options

After generating code, you have two options:

1. **Copy to Clipboard** - Click "Copy" to copy the code
2. **Download as File** - Click "Download" to save as a `.rb` file

### Integrating with Your Project

1. Save the generated file to your project's conventional directory:
   - Tools: `lib/tools/` or `agents/lib/tools/`
   - Agents: `lib/agents/` or `agents/lib/agents/`

2. The ADK web server will **automatically load** these files on startup (see [Auto-Loading Custom Code](auto_loading.md))

3. Or manually require them in your application:
   ```ruby
   require_relative 'lib/tools/my_tool'
   require_relative 'lib/agents/my_agent'
   ```

### Customizing Generated Code

The generated code is a starting point. You may want to:

- Adjust the instruction/system prompt for your specific use case
- Add additional error handling
- Modify parameter validation
- Add authentication for API tools
- Customize the model and temperature settings

## Best Practices

### Writing Good Descriptions

1. **Be specific** about what the agent/tool should do
2. **Mention tools** you want the agent to use
3. **Describe the workflow** for multi-step processes
4. **Include constraints** or requirements (e.g., "must handle errors gracefully")

### Security Considerations

- Generated code uses `ENV` variables for secrets - never hardcode API keys
- Review generated webhook validators before using in production
- Test generated HTTP tools against your actual APIs

### Iterating on Designs

1. Generate initial code from your description
2. Review and identify improvements
3. Click "Regenerate" with an updated description
4. Repeat until satisfied

## Troubleshooting

### "AI service returned empty response"

The Gemini API may occasionally return empty responses. Click "Regenerate" to try again.

### Generated code references non-existent tools

The generator is instructed to only use available tools. If you see tools that don't exist, it may be suggesting you create them. Check the comments in the generated code for guidance.

### API key errors

Ensure `GOOGLE_API_KEY` is set in your environment for the generator to work.

## Related Documentation

- [Auto-Loading Custom Code](auto_loading) - How to auto-load your custom tools and agents
- [Built-in Tools](../tools/adk_built_in_tools) - Available tools for agents
- [Agent Lifecycle](../core_concepts/adk_agent_lifecycle) - Understanding agent execution
- [Webhooks](webhooks) - Configuring webhook-enabled agents

