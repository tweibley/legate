# AI-Powered Code Generators

This guide explains how to use the AI-powered code generators to quickly create agents and tools from natural language descriptions.

## Overview

Legate includes two AI-powered generators that use Google's Gemini AI to create production-ready Ruby code:

1. **Agent Generator** - Creates complete `AgentDefinition` code for any type of agent
2. **Tool Generator** - Creates complete `Tool` class code with proper DSL and patterns

Both generators are accessible from the **Web UI** and the **CLI**, producing Ruby code that you can integrate into your projects.

## CLI Commands

The AI generators are available via the command line, with full support for piping:

### Agent Generation

```bash
# Inline description
legate agent ai_generate -d "An agent that helps with customer support"

# From a file
legate agent ai_generate -f prompt.txt -o ./agents/support_agent.rb

# Via stdin (automatically outputs to stdout)
echo "A calculator agent" | legate agent ai_generate > calc_agent.rb
```

### Tool Generation

```bash
# Inline description
legate tool ai_generate -d "A tool that converts temperatures"

# Via stdin (pipe-friendly)
echo "A URL status checker" | legate tool ai_generate > url_checker.rb
```

### CLI Options

| Option | Description |
|--------|-------------|
| `-d, --description` | Inline description |
| `-f, --prompt-file` | Read description from file |
| `-o, --output` | Output file path |
| `--stdout` | Force output to stdout |
| `--force` | Overwrite existing file |

> **Note:** When input comes from stdin, output automatically goes to stdout for pipe-friendly workflows.

## Web UI - Agent Generator


### Accessing the Generator

1. Navigate to the **Agents** page (`/agents`)
2. Click the **"Build with AI Builder"** button
3. A modal opens. Describe your agent, then click **Generate**.

### The build flow (live — no download or restart)

Unlike the CLI (which emits a `.rb` file you place yourself), the Web UI builder is
**live**:

1. **Generate** — the AI returns a *structured* agent definition (name, model, type,
   instruction, tools), not raw code.
2. **Review & tweak** — an editable form is pre-filled. Adjust the name, model, agent
   type, description, instruction, and tool selection.
3. **Add to Legion** — registers the agent into the running instance immediately. It
   shows up in the dashboard right away — nothing to download, place, or restart.
4. **Export `.rb`** (optional) — expand *"View / export generated Ruby"* to copy or
   download the equivalent definition for source control.

Agents added this way live in memory (like any agent created from the dashboard form)
until you persist them — see [Persisting runtime agents](#persisting-runtime-agents).

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

require 'legate'

definition = Legate::AgentDefinition.new.define do |a|
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

Legate::GlobalDefinitionRegistry.register(definition)
```

### Supported Agent Types

The generator can create:

| Type | Description | Key DSL Methods |
|------|-------------|-----------------|
| **LLM Agent** | Standard AI agent with tools | `use_tool`, `model_name`, `temperature` |
| **Sequential Agent** | Runs sub-agents in order | `agent_type :sequential`, `sequential_sub_agents(*names)` |
| **Parallel Agent** | Runs sub-agents concurrently | `agent_type :parallel`, `parallel_sub_agents(*names)` |
| **Loop Agent** | Repeats until condition met | `agent_type :loop`, `loop_sub_agents(*names)`, `loop_max_iterations(max)`, `loop_condition(key, value)` |
| **Webhook Agent** | Triggered by HTTP webhooks | `webhook_enabled`, `webhook_transformer`, `webhook_validator` |

### Available Tools

The generator is given the full list of tools registered in your installation
(names, descriptions, and parameters). It is instructed to use only those, and any
tool it nonetheless invents is filtered out server-side — so an agent never ends up
referencing a tool that doesn't exist.

### Suggested tools to create

If your description needs a capability that **no installed tool** provides, the
builder doesn't fake it — it lists the missing capability under **"Suggested tools to
create"** in the review step, each with a one-line description and a **Build →**
button. "Build →" opens the [Tool Generator](#tool-generator) pre-filled. Once you
build and install that tool, you're returned to the agent builder with the new tool
**added and checked**, ready to **Add to Legion**. This closes the loop:

> describe an agent → it spots a missing tool → build it inline → it loads live →
> the agent picks it up → Add to Legion.

## Tool Generator

### Accessing the Generator

1. Navigate to the **Tools** page (`/tools`)
2. Click the **"Generate with AI"** button
3. A modal dialog will open with an input form

### Describing Your Tool

Describe what you want the tool to do. The AI will automatically determine the best tool type:

- **Simple Tool**: Local computations, data transformations
- **HTTP API Tool**: External API calls with proper error handling
- **Async Tool**: Long-running background tasks via threaded execution

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

require 'legate/tool'

class TemperatureConverter < Legate::Tool
  tool_description 'Converts temperatures between units'
  
  parameter :value,
    type: :numeric,
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

Legate::GlobalToolManager.register_tool(TemperatureConverter)
```

#### HTTP API Tool

```ruby
# frozen_string_literal: true

require 'legate/tool'
require 'legate/tools/base/http_client'

class WeatherTool < Legate::Tool
  include Legate::Tools::Base::HttpClient
  
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
  rescue Legate::ToolHttpError => e
    { status: :error, error_message: "API error: #{e.message}" }
  end
end

Legate::GlobalToolManager.register_tool(WeatherTool)
```

#### Async Tool

```ruby
# frozen_string_literal: true

require 'legate/tools/base_async_job_tool'

class FileProcessorTool < Legate::Tools::BaseAsyncJobTool
  tool_description 'Processes large files in the background'

  parameter :file_path,
    type: :string,
    description: 'Path to the file to process',
    required: true

  # The worker class whose #perform method runs in the background thread.
  def worker_class
    FileProcessorWorker
  end

  # Build the (JSON-serializable) arguments passed to the worker's #perform,
  # after the job id. The base class returns { status: :pending, job_id: ... }.
  def prepare_job_arguments(params, _context)
    [params[:file_path]]
  end
end

# The worker performs the actual work and stores its status/result.
class FileProcessorWorker
  def perform(jid, file_path)
    Legate::Tools::BaseAsyncJobTool.store_job_pending(jid)
    result = process_file(file_path) # your processing logic
    Legate::Tools::BaseAsyncJobTool.store_job_result(jid, result)
  rescue StandardError => e
    Legate::Tools::BaseAsyncJobTool.store_job_error(jid, e.message, e.class.name)
  end
end

Legate::GlobalToolManager.register_tool(FileProcessorTool)
```

## Adding generated code to a running instance

The Web UI builder is designed so you rarely need to download and place files.

### Agents — "Add to Legion" (always live)

Adding a generated agent registers it straight into the running instance — it's pure
configuration, no code executes — and it appears in the dashboard immediately.

<a id="persisting-runtime-agents"></a>
#### Persisting runtime agents

Runtime-added agents (like any agent created from the dashboard form) live in memory
and are lost on restart. To make one durable, open the agent's detail page and use
**⋮ → Save to `agents/`**. This writes `agents/<name>.rb` (via the same generator as
*Download Ruby*), which the server re-loads automatically on the next start (see
[Auto-Loading Custom Code](auto_loading)).

### Tools — "Add Tool to Legion" (gated live install)

A generated tool is a Ruby class with an LLM-written `perform_execution`, so loading
it **executes code in the server process**. The Tool builder therefore offers a live
**Add Tool to Legion** action only when enabled, behind an explicit confirmation:

*   Controlled by `Legate.config.allow_runtime_tool_load` — **ON outside production,
    OFF in production** by default (see
    [Configuration → Runtime Tool Loading](../core_concepts/legate_configuration)).
*   You must tick a confirmation acknowledging the code runs on the server.
*   The source is re-validated server-side (`CodeValidator`) before loading, and a
    failing tool is isolated so it can't crash the server.
*   On install it writes `tools/<name>.rb` — durable, auditable, re-loaded next boot.
*   When disabled, the builder offers **Download** instead: save the file under
    `tools/` and restart to activate it.

> **Security:** `CodeValidator` is a *denylist*, not a sandbox, and Ruby cannot be
> meaningfully sandboxed in-process. Keep runtime tool loading enabled only where you
> trust whoever can reach the (Basic-Auth-protected) web UI.

### Download / manual placement

Both builders keep **Copy** and **Download `.rb`** for source-control workflows. To
place files by hand:

- Tools: `lib/tools/` or `agents/lib/tools/` (or `tools/`)
- Agents: `lib/agents/` or `agents/lib/agents/` (or `agents/`)

The Legate web server **automatically loads** these on startup (see
[Auto-Loading Custom Code](auto_loading)), or you can `require` them yourself.

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

### The agent needs a tool that doesn't exist

The Web UI agent builder filters out any tool that isn't installed, so a generated
agent never references a missing tool. The gap instead shows up under **"Suggested
tools to create"** in the review step with a **Build →** button — build and install
that tool, and it's added back to the agent. (The CLI/`.rb` path can't do this and
will note the gap in a code comment.)

### API key errors

Ensure `GOOGLE_API_KEY` is set in your environment for the generator to work.

## Related Documentation

- [Auto-Loading Custom Code](auto_loading) - How to auto-load your custom tools and agents
- [Built-in Tools](../tools/legate_built_in_tools) - Available tools for agents
- [Agent Lifecycle](../core_concepts/legate_agent_lifecycle) - Understanding agent execution
- [Webhooks](webhooks) - Configuring webhook-enabled agents




