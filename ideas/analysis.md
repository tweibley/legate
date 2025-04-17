Okay, let's evaluate the tool systems described in the Python ADK documentation and compare them thoroughly with your `adk-ruby` implementation.

**Python ADK Tool System Overview (Based on Description)**

The Python ADK provides a flexible tool system categorized as follows:

1.  **Built-in Tools:** Ready-to-use tools for common capabilities, requiring minimal configuration.
    *   `google_search`: Performs web searches using Google Search (requires Gemini 2).
    *   `built_in_code_execution`: Executes Python code snippets (requires Gemini 2).
    *   `vertex_ai_search_tool`: Searches configured Vertex AI Search private data stores.
    *   *Limitations:* Currently supports only one built-in tool per agent; built-in tools cannot be used in sub-agents (but seem usable via `AgentTool`).

2.  **Function Tools (Custom):** Allow developers to integrate custom logic.
    *   **Simple Function Tool:** Wraps a standard Python function. The function's docstring becomes the tool description, and parameters are derived from the signature. Returns a dictionary (preferred) or gets wrapped. Emphasizes simple types and descriptive naming.
    *   **Long Running Function Tool:** Wraps a Python *generator* function (`yield`). Allows the tool to report intermediate progress updates (via `yield`) back to the LLM/user before completing (via `return`). Useful for tasks like waiting for human input or long computations.
    *   **Agent-as-a-Tool (`AgentTool`):** Wraps another agent instance, allowing delegation. The calling agent receives the *summarized* response from the tool agent by default (can be disabled with `skip_summarization`). Differentiates from "sub-agents" where control is fully transferred.

3.  **MCP Integration Tools:**
    *   **`MCPToolset`:** Allows an ADK agent to act as an MCP client, connecting to external MCP servers (via Stdio or SSE) and using the tools they expose. Handles connection lifecycle.
    *   **Exposing ADK Tools via MCP:** Provides utilities (`adk_to_mcp_tool_type`) and guidance for building an MCP server that wraps and exposes ADK tools to any MCP client.

4.  **Authentication Framework:**
    *   A system for handling authenticated API calls within tools.
    *   Uses `AuthScheme` (how the API expects credentials) and `AuthCredential` (initial info like client ID/secret, API key).
    *   Supports API Key, OAuth2, OIDC, Service Account flows.
    *   Handles automatic token exchange and interactive OAuth/OIDC flows via special `adk_request_credential` function calls and client-side handling.
    *   Provides `ToolContext` for custom tools to access auth state, request credentials, and manage tokens within the session state (with security warnings about storage).

**`adk-ruby` Tool System Overview**

Your `adk-ruby` library has a solid foundation for tools:

1.  **Core Structure:**
    *   Base class `ADK::Tool` with `define_metadata` for name, description, parameters (including type and required status).
    *   Automatic registration via `ADK::ToolRegistry`.
    *   Standard execution flow: `execute` calls `validate_params` then `perform_execution`.
    *   `perform_execution` returns a standard hash: `{ status: :success/:error, result/error_message: ... }`.

2.  **Provided Tools:**
    *   `Echo`: Simple message echoing.
    *   `Calculator`: Basic arithmetic.
    *   `CatFacts`: External API call (GET, no auth) using Faraday.
    *   `RandomNumberTool`: Generates random integers.
    *   `AgentTool`: Delegates a task to another agent *definition* loaded from **Redis**. Instantiates the target agent ephemerally, runs the task in a temporary *in-memory* session, and returns the **raw** result/event from the target agent (no built-in summarization).

**Comparison: Python ADK vs. `adk-ruby` Tools**

| Feature                      | Python ADK Description                                                                                                                            | `adk-ruby` Implementation (`lib/adk/tool*.rb`)                                                                                                                            | Similarity | Notes                                                                                                                                                                                                                                                                  |
| :--------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :--------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Core Definition**        | `BaseTool` concept, schema definition (via docstrings/decorators), focus on returning dicts.                                                      | `ADK::Tool` base class, `define_metadata` for schema (name, desc, params), standard return hash `{status:, ...}`.                                                             | High       | Both have a base class, schema definition, and a standardized return format. Ruby's `define_metadata` is more explicit than relying solely on docstrings.                                                                                                                  |
| **Tool Registration**      | Implicit via inheritance or explicit registration? (Doc implies automatic integration when passed to Agent).                                        | Automatic via `define_metadata` calling `ADK::ToolRegistry.register`.                                                                                                       | High       | Both integrate tools easily. Ruby's explicit registration call within `define_metadata` is clear.                                                                                                                                                                        |
| **Built-in Tools**         | `google_search`, `built_in_code_execution`, `vertex_ai_search_tool`. Specific limitations mentioned.                                                | `Echo`, `Calculator`, `CatFacts`, `RandomNumberTool`, `AgentTool`. No direct equivalents to Python's built-ins.                                                            | Low        | `adk-ruby` provides basic utility tools but lacks the powerful, integrated Google-specific built-ins described for Python. The limitations mentioned for Python built-ins don't apply as Ruby lacks them.                                                                 |
| **Custom Tool (Simple Fn)** | Wrap a Python function directly. Docstring becomes description.                                                                                   | Create a class inheriting `ADK::Tool`, implement `perform_execution`. Metadata defined via `define_metadata`.                                                             | Moderate   | Python offers a more direct function-wrapping shortcut. Ruby requires creating a dedicated class, which is slightly more verbose but perhaps more structured and consistent with other tools.                                                                               |
| **Custom Tool (Long Run)** | `LongRunningFunctionTool` wraps a generator (`yield` for progress, `return` for final).                                                            | **Not Implemented.** No equivalent concept for yielding progress updates from a tool. Tools execute synchronously within the agent's turn.                                  | Low        | Significant difference. Ruby tools are blocking within the step execution.                                                                                                                                                                                             |
| **Custom Tool (Agent)**    | `AgentTool` wraps another *Agent instance*, returns *summarized* response by default. Differentiates from sub-agents.                               | `ADK::Tools::AgentTool` wraps an agent *definition loaded from Redis*, returns *raw* result/event from target agent. No concept of sub-agents defined.                     | Moderate   | Both allow delegation. Key differences: Ruby uses Redis definitions vs. Python instances, and Ruby returns raw results vs. Python's default summarization. Ruby's approach depends on Redis persistence for definitions.                                                      |
| **MCP Integration**        | `MCPToolset` to use external MCP tools. Utilities (`adk_to_mcp_tool_type`) to expose ADK tools via an MCP server.                                  | **Not Implemented.** No support for connecting to MCP servers or exposing tools via MCP.                                                                                    | Low        | `adk-ruby` doesn't currently engage with the Model Context Protocol standard.                                                                                                                                                                                          |
| **Authentication**         | Comprehensive framework: `AuthScheme`, `AuthCredential`, `ToolContext`, automatic token exchange, interactive flow handling (`adk_request_credential`). | **Not Implemented.** No built-in authentication framework. `CatFacts` tool makes unauthenticated requests. No mechanism described for handling OAuth, API keys, etc. | Low        | Major gap compared to the described Python features. Ruby tools currently cannot easily interact with authenticated APIs in a standardized way.                                                                                                                        |
| **Parameter Validation**   | Mentioned for function tools (simple types). Base tool likely handles required params.                                                              | `ADK::Tool#validate_params` checks for required parameters based on metadata. Type validation mentioned as future possibility in `next-steps.md`.                           | High       | Both handle required parameter checks. Ruby's metadata explicitly includes type hints, though validation isn't implemented yet.                                                                                                                                  |
| **Tool Context Access**    | Custom function tools receive `ToolContext` to access state (`tool_context.state`) and auth (`tool_context.request_credential`, `get_auth_response`). | Ruby tools currently receive only the validated `params` hash in `perform_execution`. They don't automatically get access to the session/state or a dedicated context object. | Low        | Python tools have richer context, enabling state interaction and auth flows. Ruby tools are currently isolated with only their input parameters.                                                                                                                         |

**Evaluation Summary**

*   **Strengths of `adk-ruby`:**
    *   Clear and explicit tool definition via `define_metadata`.
    *   Solid base class (`ADK::Tool`) and registry (`ADK::ToolRegistry`).
    *   Standardized success/error return structure.
    *   Good set of basic utility tools provided (`Echo`, `Calculator`, `RandomNumber`, `CatFacts`).
    *   Interesting `AgentTool` for delegation based on persisted definitions (though different from Python's).
*   **Weaknesses/Gaps in `adk-ruby` (Compared to Python Description):**
    *   **Lack of Powerful Built-ins:** No direct equivalents for Google Search, Code Execution, or Vertex AI Search, limiting out-of-the-box capabilities significantly.
    *   **No Long-Running Tool Support:** Cannot handle tasks that require yielding progress or waiting for external input without blocking the agent.
    *   **No Authentication Framework:** This is a critical gap for building agents that interact with most real-world APIs (Google services, Salesforce, custom enterprise APIs, etc.).
    *   **No MCP Integration:** Misses out on the potential interoperability offered by the MCP standard.
    *   **Limited Tool Context:** Tools lack access to session state or other contextual information beyond their direct parameters, limiting their ability to perform more complex, stateful operations or participate in auth flows.
    *   **AgentTool Differences:** While functional, the reliance on Redis definitions and lack of summarization differs from the Python approach.

**Recommendations & PRD for Missing Features in `adk-ruby`**

Here are recommendations structured as PRD sections for key missing features:

---

**PRD 1: Built-in Google Search Tool**

1.  **Feature Name:** Built-in Google Search Tool
2.  **Goal/Problem:** Enable agents to access real-time information from the public web to answer user questions accurately and timely. Agents currently lack this capability out-of-the-box.
3.  **User Story:** As a developer, I want to add a pre-configured `google_search` tool to my ADK agent, so the agent can use Google Search to find information relevant to the user's query without me writing the search API integration logic.
4.  **Functional Requirements (FR):**
    *   FR1: Define a new tool class `ADK::Tools::GoogleSearch` inheriting from `ADK::Tool`.
    *   FR2: The tool's metadata should define it as `:google_search` with appropriate description and parameters (e.g., `query: { type: :string, required: true }`).
    *   FR3: The tool must integrate with a Google Search API (e.g., Google Custom Search JSON API or potentially leverage Gemini's built-in search if the `gemini-ai` gem exposes it sufficiently).
    *   FR4: The tool must accept a Google API Key and potentially a Custom Search Engine ID for configuration (likely via ENV variables or initialization options).
    *   FR5: `perform_execution` should take the `query` parameter, execute the search against the configured API.
    *   FR6: `perform_execution` must parse the API response, extracting relevant search results (e.g., snippets, titles, links).
    *   FR7: `perform_execution` must return a standard `{ status: :success, result: <formatted_results> }` hash on success, where `<formatted_results>` is a string or structured data (e.g., Array of Hashes) easily consumable by the LLM planner/agent.
    *   FR8: `perform_execution` must handle API errors (invalid key, quota exceeded, no results) and return a standard `{ status: :error, error_message: ... }` hash.
    *   FR9: The tool should be automatically registered in `ADK::ToolRegistry`.
5.  **Non-Functional Requirements (NFR):**
    *   NFR1: API credentials must be handled securely (read from ENV or config, not hardcoded).
    *   NFR2: Network timeouts and connection errors must be handled gracefully.
    *   NFR3: Result formatting should prioritize information useful for LLM reasoning.
6.  **Dependencies:**
    *   Likely `google-api-client` gem or modifications to use `gemini-ai`'s search features if applicable.
    *   Faraday or similar HTTP client if calling REST API directly.
    *   Google Cloud Project with Search API enabled and an API Key.
7.  **Acceptance Criteria (AC):**
    *   AC1: Developer can add `:google_search` to an agent's tool list.
    *   AC2: Agent's planner correctly generates a step using the `:google_search` tool with a query parameter.
    *   AC3: When executed with a valid query and API key, the tool returns a `{ status: :success }` hash containing search results.
    *   AC4: When executed with an invalid API key or network error, the tool returns a `{ status: :error }` hash with a descriptive message.

---

**PRD 2: Structured Authentication Framework**

1.  **Feature Name:** Tool Authentication Framework
2.  **Goal/Problem:** Enable ADK tools to securely interact with APIs requiring authentication (OAuth2, API Keys, etc.). Currently, there's no standard way for tools to manage credentials or handle interactive auth flows.
3.  **User Story:**
    *   As a developer creating a custom tool, I want to access session-specific credentials (like OAuth tokens) obtained via user interaction, so my tool can call protected APIs.
    *   As a developer using a tool requiring OAuth, I want the ADK framework to handle the interactive consent flow with the user and provide the resulting token to the tool automatically upon retry.
    *   As a developer, I want to configure tools with API keys or Service Account credentials securely.
4.  **Functional Requirements (FR):**
    *   **FR1: Define Authentication Configuration Classes:**
        *   `ADK::Auth::AuthScheme`: Base class/module for auth types (e.g., `ApiKeyScheme`, `OAuth2Scheme`). Define necessary fields (e.g., `tokenUrl`, `authorizationUrl`, `scopes` for OAuth2; `in`, `name` for ApiKey).
        *   `ADK::Auth::AuthCredential`: Base class/module for initial credentials (e.g., `ApiKeyCredential`, `OAuth2Credential` with client\_id/secret, `ServiceAccountCredential`).
        *   `ADK::Auth::AuthConfig`: Container holding both the required `AuthScheme` and the initial `AuthCredential`.
    *   **FR2: Tool Configuration:** Allow `ADK::Tool` subclasses (or specific tool initializers) to declare their required `AuthConfig`.
    *   **FR3: Tool Context:**
        *   Introduce an `ADK::ToolContext` object.
        *   Pass `ToolContext` to `perform_execution` alongside `params`.
        *   `ToolContext` must provide access to the current `ADK::Session` (read-only access to events, read/write access to *scoped* state via methods).
        *   `ToolContext` must provide methods for the auth flow:
            *   `request_credential(auth_config)`: Signals the framework that auth is needed. Tool returns a "pending" status.
            *   `get_auth_response`: Allows the tool (on retry) to check if the client provided auth results (e.g., callback URL/code). Returns an updated `AuthConfig` or similar structure.
    *   **FR4: Framework Handling (Runner/Agent):**
        *   Detect when a tool calls `request_credential`.
        *   Pause execution and generate a special event/signal (similar to Python's `adk_request_credential` function call) containing the necessary `AuthConfig` details (like `auth_uri`).
        *   Receive the response from the client (containing the callback URL/code within an updated `AuthConfig` or similar).
        *   Perform automatic token exchange (for OAuth2/OIDC) using the received code and stored client secret. Store the obtained token(s) securely, potentially linked to the session state via `ToolContext`.
        *   Automatically retry the original tool call, making the obtained token available via `ToolContext`.
    *   **FR5: Session State Integration:** Define specific state key prefixes/scopes (e.g., `auth:`, `session:auth:`) for storing tokens securely within the session state, accessible via `ToolContext`.
    *   **FR6: Secure Credential Handling:** Emphasize reading initial credentials (API keys, client secrets) from secure sources (ENV variables, config files) and avoid hardcoding. Provide guidance on securely storing refresh tokens if applicable (encryption, external secret manager).
5.  **Non-Functional Requirements (NFR):**
    *   NFR1: Security is paramount. Minimize exposure of secrets. Clear guidelines on storing tokens.
    *   NFR2: Framework should handle common OAuth2/OIDC grant types (Authorization Code).
    *   NFR3: Error handling for failed token exchange or invalid client responses.
6.  **Dependencies:**
    *   OAuth2 client library (e.g., `oauth2` gem).
    *   Google Auth library if supporting Service Accounts (`googleauth`).
    *   Potentially a cryptography library for encrypting stored tokens.
7.  **Acceptance Criteria (AC):**
    *   AC1: A developer can define a tool requiring OAuth2.
    *   AC2: When the tool runs without credentials, the framework signals the client application for user interaction, providing an auth URL.
    *   AC3: The client application can simulate the redirect and send the callback URL/code back to the framework.
    *   AC4: The framework successfully exchanges the code for a token.
    *   AC5: The framework retries the tool, providing the token via `ToolContext`.
    *   AC6: The tool successfully uses the token (mocked API call).
    *   AC7: A developer can configure a tool with an API Key, and the tool receives it for use.

---

**PRD 3: Long-Running Function Tool Support**

1.  **Feature Name:** Long-Running Tool Support
2.  **Goal/Problem:** Allow tools to perform long-running operations (e.g., complex calculations, external processes, waiting for human input) without blocking the agent and provide progress updates.
3.  **User Story:** As a developer, I want to create a tool that performs a multi-step, time-consuming task and yields intermediate status updates back to the agent/user, so the user knows the task is progressing and the agent isn't frozen.
4.  **Functional Requirements (FR):**
    *   FR1: Introduce a mechanism for a tool's `perform_execution` to indicate it's long-running and yield intermediate results. Ruby's `Fiber` or `Enumerator::Lazy` might be suitable analogs to Python's generators.
    *   FR2: The framework (Agent/Runner) must recognize these yielded intermediate results.
    *   FR3: Each yielded result should be packaged as a distinct `ADK::Event` (e.g., `role: :tool_result`, `status: :pending`, `content: <yielded_data>`) and sent back through the normal event stream.
    *   FR4: The tool must signal completion, likely via the final return value from `perform_execution` (or the end of the Fiber/Enumerator).
    *   FR5: The final completion signal should result in a final `ADK::Event` (e.g., `role: :tool_result`, `status: :success/:error`, `content: <final_result>`).
    *   FR6: The Agent/Planner needs awareness (potentially via tool metadata or event flags) that a tool is long-running, allowing it to potentially continue with other tasks or inform the user appropriately based on intermediate updates. *(This is complex and may be a follow-on)*.
    *   FR7: Need clear conventions for the structure of yielded progress updates (e.g., hash with `:status`, `:progress`, `:message`).
5.  **Non-Functional Requirements (NFR):**
    *   NFR1: The mechanism should integrate cleanly with the existing event flow.
    *   NFR2: Resource management for the long-running operation (e.g., Fibers) needs consideration.
6.  **Dependencies:** None directly, relies on Ruby core features.
7.  **Acceptance Criteria (AC):**
    *   AC1: A tool can be defined that yields multiple status updates before returning a final result.
    *   AC2: The agent receives separate events for each yielded update and the final result.
    *   AC3: The agent (or calling application) can distinguish between intermediate updates and the final completion event.

---

**PRD 4: Built-in Code Execution Tool**

1.  **Feature Name:** Built-in Code Execution Tool
2.  **Goal/Problem:** Enable agents to perform calculations, data manipulation, and other tasks by executing sandboxed code snippets, similar to the Python ADK capability.
3.  **User Story:** As a developer, I want to give my agent a `code_execution` tool so it can run simple Ruby code generated by the LLM to answer specific calculation or logic questions.
4.  **Functional Requirements (FR):**
    *   FR1: Define `ADK::Tools::CodeExecution` inheriting `ADK::Tool`.
    *   FR2: Metadata: Name `:code_execution`, description, parameter `code: { type: :string, required: true }`.
    *   FR3: **Security:** `perform_execution` MUST execute the provided `code` string in a **secure sandbox**. This is CRITICAL. Options:
        *   Use a sandboxing gem (e.g., `sandbox`, evaluate carefully for security).
        *   Execute in a separate, tightly controlled process or container with limited permissions.
        *   *Avoid `eval` or `instance_eval` on untrusted input directly.*
    *   FR4: Capture stdout, stderr, and the return value from the executed code.
    *   FR5: Handle execution timeouts to prevent runaway code.
    *   FR6: Return `{ status: :success, result: { stdout: ..., stderr: ..., return_value: ... } }` on successful execution.
    *   FR7: Return `{ status: :error, error_message: ..., stderr: ... }` if the code raises an exception, times out, or fails to execute.
5.  **Non-Functional Requirements (NFR):**
    *   NFR1: **Security:** The sandbox must effectively prevent malicious code execution (filesystem access, network calls, environment variable access, etc.). This is the hardest NFR.
    *   NFR2: Performance: Sandbox overhead should be acceptable.
    *   NFR3: Reliability: Sandbox should consistently execute valid code and report errors clearly.
6.  **Dependencies:** A suitable sandboxing library or mechanism.
7.  **Acceptance Criteria (AC):**
    *   AC1: Agent can use the tool to execute simple Ruby code (e.g., `1 + 2`).
    *   AC2: Tool returns the correct stdout/return value for successful execution.
    *   AC3: Tool returns an error status for code that raises exceptions.
    *   AC4: Tool prevents potentially harmful code (e.g., `system('rm -rf /')`, file access) from executing outside the sandbox. (Requires thorough security testing).

---

These PRDs provide a starting point for implementing features to bring `adk-ruby` closer in capability to the described Python ADK, focusing on the most impactful areas like authentication and core built-in tools.