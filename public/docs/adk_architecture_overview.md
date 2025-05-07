# ADK Architecture Overview

This document provides a high-level overview of the ADK (Agent Development Kit) library, its core components, and how they interact to enable the development and operation of AI agents.

## Core Components Diagram

The following diagram illustrates the main architectural components of the ADK:

```mermaid
graph TD
    subgraph UserInteraction ["User Interaction"]
        CLI[ADK CLI]
        WebUI[ADK Web UI]
    end

    subgraph ADKCore ["ADK Core"]
        Agent["ADK::Agent"]
        Planner["ADK::Planner"]
        ToolRegistry["ADK::ToolRegistry"]
        SessionService["ADK::SessionService"]
        DefinitionStore["ADK::DefinitionStore"]
        GlobalToolMgr["ADK::GlobalToolManager"]
    end

    subgraph ToolsAndExecution ["Tools & Execution"]
        GenericTool["ADK::Tool"]
        LLM["Language Model (LLM)"]
        ExternalServices["External APIs/Services"]
    end

    UserInteraction -- Manages/Interacts with --> Agent
    UserInteraction -- Manages/Interacts with --> DefinitionStore

    Agent -- Uses --> Planner
    Agent -- Uses --> ToolRegistry
    Agent -- Uses --> SessionService
    Agent -- Loads Definition from --> DefinitionStore

    Planner -- Uses --> ToolRegistry
    Planner -- Communicates with --> LLM

    ToolRegistry -- Contains/Manages --> GenericTool
    ToolRegistry -- Populated by --> GlobalToolMgr
    GlobalToolMgr -- Discovers --> GenericTool

    Agent -- Executes --> GenericTool
    GenericTool -- Can call --> ExternalServices
    GenericTool -- Can interact with --> SessionService

    style Agent fill:#ccf,stroke:#333,stroke-width:2px
    style Planner fill:#cff,stroke:#333,stroke-width:2px
    style ToolRegistry fill:#cfc,stroke:#333,stroke-width:2px
    style GenericTool fill:#cfc,stroke:#333,stroke-width:2px
    style SessionService fill:#fcc,stroke:#333,stroke-width:2px
    style DefinitionStore fill:#fcc,stroke:#333,stroke-width:2px
    style LLM fill:#f9f,stroke:#333,stroke-width:2px
```

## Component Descriptions

*   **User Interaction (CLI/Web UI):** Interfaces for users to create, manage, and interact with agents and their definitions.
*   **`ADK::Agent`:** The central orchestrator. It manages the execution of tasks, interacts with the planner, tools, and session service based on its definition.
*   **`ADK::Planner`:** Responsible for creating a sequence of steps (a plan) for the agent to follow to accomplish a given task. It uses the agent's instructions, available tools, and conversation history, often leveraging an LLM.
*   **`ADK::ToolRegistry`:** An instance-specific collection of tools available to a particular agent. It provides tool metadata to the planner and tool instances to the agent for execution.
*   **`ADK::GlobalToolManager`:** A global registry where tool classes are registered. The `ToolRegistry` of an agent is typically populated from this manager.
*   **`ADK::Tool`:** Represents a specific capability or action an agent can perform (e.g., calculator, web search, API call). Tools have defined metadata (name, description, parameters) and an execution method.
*   **`ADK::SessionService`:** Manages the state of an agent's conversation over time, including history of prompts, tool calls, and responses. Common implementations are `InMemory` and `Redis`.
*   **`ADK::DefinitionStore`:** Stores and retrieves agent definitions (configurations like name, instructions, tools to use, model, etc.). Typically backed by Redis.
*   **Language Model (LLM):** An external AI model (e.g., from OpenAI, Google) that the planner consults to generate plans and that the agent may use to generate final responses.
*   **External APIs/Services:** Third-party services that `ADK::Tool`s might interact with to perform their actions.

## Basic Workflow

A typical agent task execution involves the following simplified flow:

1.  **User Input:** A user provides a prompt or task to an `ADK::Agent` via a CLI or Web UI, usually associated with a `session_id`.
2.  **Agent Activation:** The `ADK::Agent` loads its definition and retrieves the session history using the `ADK::SessionService`.
3.  **Planning:** The agent invokes the `ADK::Planner`. The planner, using the agent's instructions, available tool metadata (from `ADK::ToolRegistry`), and conversation history, consults an LLM to create a plan (a sequence of tool calls).
4.  **Tool Execution:** The agent iterates through the plan:
    *   For each step, it retrieves the appropriate `ADK::Tool` from its `ToolRegistry`.
    *   It executes the tool with the parameters specified in the plan.
    *   The tool performs its action (potentially calling external APIs) and returns a result.
    *   The agent records the tool call and its result in the session history via the `ADK::SessionService`.
5.  **Response Generation:** After plan completion (or if no plan is needed), the agent may use an LLM to generate a final response based on the task and tool results.
6.  **Output:** The agent returns the final response or result to the user, and this event is also saved to the session history.

## Key Concepts

*   **Agent Definition:** The configuration of an agent, specifying its behavior, instructions, and capabilities (tools, model).
*   **Session:** A record of an interaction or conversation with an agent over time, identified by a `session_id`. It includes all events like user prompts, tool calls, and agent responses.
*   **Tool Metadata:** The information that describes a tool to the planner and LLM, including its name, a description of what it does, and the parameters it accepts.
*   **Plan:** A sequence of steps (primarily tool calls) generated by the planner for the agent to execute to achieve a goal.

## Further Reading

For more detailed information on specific components, refer to:

*   `adk_agent_lifecycle.md` (Coming Soon)
*   `adk_tools_and_registry.md` (Coming Soon)
*   `http_client_usage.md`
*   `mcp_client_integration.md`
*   `mcp_server_exposure.md`
*   `configuring_agent_webhooks.md`
*   `sending_outbound_webhooks.md` 