# Improving ADK-Ruby User Experience

Based on an analysis of the `docs/demo-plan.md` for a news aggregator agent, here are several areas where `adk-ruby` could be enhanced to reduce boilerplate code and improve the developer experience:

## 1. Tool Definition & Registration

*   **Concise Metadata DSL:**
    *   The `define_metadata` block, especially the `parameters` hash, is verbose.
    *   *Suggestion:* Explore a more concise DSL, potentially inferring the tool name from the class name (e.g., `RssFetcherTool` -> `:rss_fetcher`) and using simpler syntax for parameters, possibly leveraging type hints or conventions.

*   **Simplified Parameter Access:**
    *   Accessing parameters via `params[:key]` is functional but slightly verbose.
    *   *Suggestion:* Consider automatically mapping defined parameters to keyword arguments in the `execute` method signature (e.g., `def execute(topic:, feed_url:, max_items: 5, context: nil)`), potentially including automatic type checking based on metadata.

*   **Standardized Error Handling:**
    *   Returning `{ status: :error, error_message: ... }` requires repetitive boilerplate in tool error paths.
    *   *Suggestion:* Introduce custom exception classes (e.g., `ADK::ToolError`, `ADK::ToolArgumentError`) that tools can raise. The ADK runtime could catch these and automatically format the error event, simplifying tool code.

*   **Base Classes/Modules for Common Patterns:**
    *   Tools often include boilerplate for common tasks like API calls (e.g., `SummarizerTool` and Gemini).
    *   *Suggestion:* Provide base tool classes or modules for common integrations (e.g., `ADK::Tools::Gemini`, `ADK::Tools::HttpClient`). Users could inherit/include these and focus on the core logic (prompting, result processing), letting the base handle setup, API key management, basic request/response flow, etc.

*   **Context-Aware Logging:**
    *   The pattern `ADK.logger.info("#{self.class.name}") { ... }` is repetitive.
    *   *Suggestion:* Inject a pre-configured, context-aware logger into the tool instance (e.g., `tool_logger.info(...)`) that automatically includes the tool name or other relevant context.

## 2. Agent Setup & Execution

*   **Automatic Tool Discovery:**
    *   Explicitly `require`-ing tool files and manually instantiating them via `GlobalToolManager` adds setup steps.
    *   *Suggestion:* Implement automatic tool discovery. Allow users to specify a tool directory (e.g., `tools/`) in configuration or agent setup. ADK could automatically load `.rb` files, register the tools found, and handle instantiation, adding them to the agent implicitly or explicitly.
    *   **Update:** This is now implemented via the `tool_paths` keyword argument in `ADK::Agent#initialize`. Provide a single path string or an array of path strings pointing to directories containing tool definitions (`*.rb` files). The agent will load these files, and any tools defined within them using `define_metadata` will be automatically instantiated and added to the agent.

*   **Streamlined Agent Configuration:**
    *   Instantiating the agent, adding tools, setting up the session service, creating a session, and starting the agent involves multiple separate steps.
    *   *Suggestion:* Introduce a builder pattern or a more consolidated setup method for the agent. This could potentially hide the complexity of session management for simple use cases. Example:
        ```ruby
        agent = ADK::Agent.define do |a|
          a.name = 'news_agent'
          a.description = '...'
          a.discover_tools_in('tools/') # Auto-load and add
        end
        ```

*   **Simplified Environment Loading:**
    *   Requiring `bundler/setup`, `dotenv`, etc., adds lines to basic runner scripts.
    *   *Suggestion:* While difficult to abstract completely, investigate if `ADK.load_environment` or similar helpers could simplify common setup like loading `.env` files.

## 3. Result Handling

*   **Direct Access to Final Tool Result:**
    *   The most significant boilerplate identified is retrieving the *actual* structured result from the last tool in the plan. The current demo involves re-fetching the session, iterating through all events, and manually finding the correct `tool_result` event. This is complex, error-prone, and not user-friendly.
    *   *Suggestion:* The `agent.run_task` (or a simplified `agent.run`) method's return value **must** provide direct access to the final, parsed result data from the last successfully executed tool. The agent runtime possesses this information and should surface it directly to the caller, eliminating the need for manual event history dissection. 