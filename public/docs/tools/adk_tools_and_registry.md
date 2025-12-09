# ADK Tools and Registry

This document describes the tool system in ADK, including how tools are defined, registered, and made available to agents.

## Overview

ADK provides a robust tool system that allows agents to perform actions beyond simple text generation. Tools are Ruby classes that encapsulate specific functionality like performing calculations, making HTTP requests, or delegating tasks to other agents.

```mermaid
graph TB
    subgraph Registration
        ToolClass[Tool Class Definition] --> GTM[GlobalToolManager]
    end
    
    subgraph AgentSetup
        AgentDef[AgentDefinition] -->|use_tool :name| Agent
        Agent -->|creates| TR[ToolRegistry]
        GTM -->|populates| TR
    end
    
    subgraph Execution
        Agent -->|execute| Tool[Tool Instance]
        Tool -->|with| TC[ToolContext]
    end
    
    style GTM fill:#cfc,stroke:#333
    style TR fill:#cfc,stroke:#333
    style Tool fill:#ccf,stroke:#333
```

## Core Components

### 1. GlobalToolManager

The `ADK::GlobalToolManager` is a global registry where all tool classes are registered. It provides a central place to discover available tools.

**Key Methods:**

| Method | Description |
|--------|-------------|
| `register_tool(tool_class)` | Register a tool class globally |
| `find_class(name_symbol)` | Find a tool class by its symbolic name |
| `list_all_tools` | Get metadata for all registered tools |
| `registered_tool_names` | Get an array of all registered tool name symbols |
| `create_instance(name_symbol)` | Create a new instance of a tool by name |

**Example:**
```ruby
# Registration (typically automatic via inheritance)
ADK::GlobalToolManager.register_tool(MyCustomTool)

# Discovery
available_tools = ADK::GlobalToolManager.list_all_tools
# => [{name: :my_custom_tool, description: "...", parameters: [...]}]

# Instantiation
tool = ADK::GlobalToolManager.create_instance(:calculator)
```

### 2. ToolRegistry

The `ADK::ToolRegistry` is an instance-specific collection of tools available to a particular agent. Each agent has its own ToolRegistry, populated from the GlobalToolManager based on the agent's definition.

**Key Methods:**

| Method | Description |
|--------|-------------|
| `register(name, klass)` | Register a tool class with this registry |
| `find_class(name_symbol)` | Find a tool class by name in this registry |
| `create_instance(name_symbol)` | Create a tool instance |
| `list_tools` | Get metadata for tools in this registry |

**Relationship to Agent:**
```ruby
# When an agent is initialized, its ToolRegistry is populated
definition.tool_names.each do |tool_name|
  klass = ADK::GlobalToolManager.find_class(tool_name)
  agent.tool_registry.register(tool_name, klass)
end
```

## Defining Tools

Tools are defined by creating a class that inherits from `ADK::Tool` and uses the metadata DSL.

```ruby
class WeatherTool < ADK::Tool
  # Description shown to the LLM planner
  tool_description 'Get current weather for a location'
  
  # Define parameters the tool accepts
  parameter :location,
    type: :string,
    description: 'City name or coordinates',
    required: true
  
  parameter :units,
    type: :string,
    description: 'Temperature units: celsius or fahrenheit',
    required: false
  
  private
  
  def perform_execution(params, context)
    location = params[:location]
    units = params[:units] || 'celsius'
    
    # Tool logic here...
    
    { status: :success, result: "Weather for #{location}: 72°" }
  end
end

# Register the tool (automatic if file is auto-loaded)
ADK::GlobalToolManager.register_tool(WeatherTool)
```

### Tool Metadata DSL

The `ADK::Tool::MetadataDsl` module provides class-level methods for defining tool metadata:

| DSL Method | Purpose |
|------------|---------|
| `tool_name` | Explicitly set the tool's symbolic name |
| `tool_description` | Provide a description for the LLM |
| `parameter(name, options)` | Define an input parameter |

**Parameter Options:**

| Option | Type | Description |
|--------|------|-------------|
| `type` | Symbol | `:string`, `:integer`, `:number`, `:boolean`, `:array`, `:object` |
| `description` | String | Description for the LLM |
| `required` | Boolean | Whether the parameter is required |
| `enum` | Array | Allowed values (optional) |

### Tool Name Inference

If `tool_name` is not explicitly set, ADK infers it from the class name:

- `MyCustomTool` → `:my_custom_tool`
- `Calculator` → `:calculator`
- `ADK::Tools::CatFacts` → `:cat_facts`

## Using Tools in Agents

Tools are associated with agents via the `use_tool` method in the agent definition:

```ruby
ADK::AgentDefinition.new.define do |a|
  a.name :my_agent
  a.instruction 'You can perform calculations.'
  
  # Reference tools by their symbolic name
  a.use_tool :calculator
  a.use_tool :echo
  a.use_tool :weather_tool
end
```

## Tool Execution Flow

When an agent executes a tool:

```mermaid
sequenceDiagram
    participant Agent
    participant TR as ToolRegistry
    participant Tool
    participant TC as ToolContext
    
    Agent->>TR: find_class(:tool_name)
    TR-->>Agent: ToolClass
    Agent->>Tool: new()
    Agent->>TC: new(session_info)
    Agent->>Tool: execute(params, context)
    Tool->>Tool: validate_parameters
    Tool->>Tool: perform_execution
    Tool-->>Agent: {status: :success, result: ...}
```

1. The agent looks up the tool class in its ToolRegistry
2. It creates an instance of the tool
3. It creates a ToolContext with session information
4. It calls `execute(params, context)` on the tool
5. The tool validates parameters and runs `perform_execution`
6. The tool returns a result hash

## ToolContext

The `ADK::ToolContext` object provides tools with access to:

- Session state (`state_get`, `state_set`)
- Session ID, user ID, app name
- Invocation ID for tracking
- Authentication helpers (for tools using the auth module)

```ruby
def perform_execution(params, context)
  # Access session state
  previous_value = context.state_get(:some_key)
  
  # Set state (applied after tool completes)
  context.state_set(:result_key, 'new value')
  
  { status: :success, result: 'Done' }
end
```

## Built-in Tools

ADK provides several built-in tools:

| Tool Name | Description |
|-----------|-------------|
| `:calculator` | Performs arithmetic operations |
| `:echo` | Echoes back the input message |
| `:cat_facts` | Fetches random cat facts |
| `:random_number` | Generates random numbers |
| `:webhook_tool` | Sends outbound webhooks |
| `:delegate_task` | Delegates to another agent |
| `:check_job_status` | Checks Sidekiq job status |

See [Built-in Tools Reference](./adk_built_in_tools) for detailed documentation.

## Further Reading

*   [`adk_architecture_overview`](../core_concepts/adk_architecture_overview)
*   [`adk_built_in_tools`](./adk_built_in_tools)
*   [`auto_loading`](../guides/auto_loading)
*   [`ai_code_generators`](../guides/ai_code_generators)
