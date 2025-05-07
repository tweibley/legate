# Web UI Built-in Demos Plan

This document outlines a plan for integrating built-in demos into the ADK Web UI. The goal is to provide interactive examples that help users understand how different components of the ADK work together.

## Proposed Demos

### 1. Simple Agent Chat

*   **Goal:** Demonstrate the fundamental interaction loop between a user and a simple ADK agent via the web UI.
*   **Concept:** Show how instructions are sent to an agent, processed, and how responses are returned.
*   **Components Involved:**
    *   Agent: `examples/simple_agent.rb` or `examples/instructed_agent.rb`
    *   Web UI: A chat-like interface.
    *   Communication: Via MCP server *or* potentially direct local invocation.
*   **UI Presentation:**
    *   A dedicated "Simple Chat Demo" page in the UI.
    *   A text input area for the user to send instructions.
    *   A display area showing the conversation history (user input and agent response).
    *   Under the hood, the UI would interact with an instance of the chosen simple agent running (potentially via MCP or direct local execution).

### 2. Tool-Using Agent: Random Calculator

*   **Goal:** Illustrate how an agent can leverage defined tools to fulfill requests.
*   **Concept:** Show the process of an agent receiving an instruction, identifying the need for a tool, invoking the tool, processing the tool's output, and formulating a final response.
*   **Components Involved:**
    *   Agent: `examples/random_calculator.rb`
    *   Tools: The math tools defined within `random_calculator.rb`.
    *   Web UI: Interface to trigger the agent and view results.
    *   Communication: Via MCP server *or* direct local invocation, handling agent-tool interaction.
*   **UI Presentation:**
    *   A "Tool Agent Demo" page.
    *   An input field for the user (e.g., "add 5 and 3", "multiply 10 by 4").
    *   A display area showing:
        *   The user's request.
        *   A log/indication that the agent is calling a specific tool (e.g., "Agent calling 'add' tool with arguments: 5, 3").
        *   The result returned by the tool.
        *   The agent's final response incorporating the tool result.

### 3. Managed Resource Interaction Demo

*   **Goal:** Demonstrate how agents can interact with external resources (like data stores, files, APIs) managed through the ADK framework.
*   **Concept:** An agent receives instructions to read or modify data held by a resource server managed by the ADK. The UI shows the command, the interaction, and the result.
*   **Components Involved:**
    *   Agent: An agent designed to interact with a resource (e.g., logic similar to `examples/mcp_client_agent_example.rb` adapted for the resource).
    *   Resource Server: `examples/adk_mcp_server_resource_example.rb` or `examples/mcp_resource_server_example.rb`.
    *   Web UI: Interface to send commands like "read data" or "update data X", and display the results/status.
    *   Communication: MCP likely beneficial here to connect agent and resource server, or appropriate local setup.
*   **UI Presentation:**
    *   A "Resource Interaction Demo" page.
    *   Buttons/Input to trigger actions like "Get Resource State", "Set Resource State to [value]".
    *   A display area showing:
        *   The user's request/command sent to the agent.
        *   Indication of the agent communicating with the resource server (e.g., "Agent requesting state from ResourceServer").
        *   The response from the resource server.
        *   The final status or data displayed (e.g., "Resource state is now: [new_value]").
    *   This highlights the library's capabilities for building systems where agents interact with managed state or external services.

## Implementation Notes

*   The demos should ideally run isolated instances of the example agents/servers to avoid conflicts.
*   The Web UI needs backend logic to instantiate and communicate with these demo agents (e.g., via MCP protocol or direct local calls).
*   Clear explanations should accompany each demo in the UI to guide the user. 