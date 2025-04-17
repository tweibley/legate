# Suggestions for next steps
**A. Core Agent & Planning Robustness:**

1.  **Refine Plan Execution Logic:**
    *   **Error Handling:** Decide if `Agent#execute_plan` should stop immediately when a step returns `{ status: :error }` or continue executing subsequent steps. Implement the chosen strategy. (Currently, it continues).
    *   **Result Injection:** The current `"[Result from step... ]"` placeholder and injection logic is basic. Enhance it to potentially:
        *   Handle specific keys from a previous step's result hash (e.g., if a tool returns `{ status: :success, user_id: 123, details: {...} }`, allow the planner to specify using `user_id` in the next step). This might involve a more structured placeholder like `{{steps[0].result.user_id}}`.
        *   Allow access to results from steps other than the immediately preceding one.
2.  **Tool Parameter Type Validation:** Implement type checking within `Tool#validate_params` based on the `:type` defined in the tool's metadata (`:string`, `:integer`, `:numeric`, `:boolean`, `:array`, `:hash`). This would catch errors earlier than relying solely on `perform_execution`.
3.  **Memory/Session Integration:**
    *   Define how agent memory (`ADK::Memory`) should be used. Should chat history automatically be stored? Should the planner receive context/history from memory to inform its plans?
    *   Implement basic memory usage, perhaps storing the last N turns of a chat session or the results of recent tasks.

**B. Testing & Code Quality:**

4.  **Implement RSpec Tests:** The `Rakefile` has a `spec` task, but no tests exist. Start adding tests:
    *   Test individual tools (`Echo`, `Calculator`, etc.) – provide params, check returned hash (`status`, `result`/`error_message`).
    *   Test `ToolRegistry` (registration, listing, instance creation).
    *   Test `ADK::Agent` (initialization with model, adding tools, start/stop state, `run_task` calls with mocked planner/tools).
    *   Test `ADK::Planner` (mocking the `gemini-ai` client, checking prompt generation and response parsing/validation for single/multi-step/error cases).
    *   Add basic request specs for the Sinatra `ADK::Web::App` routes.
5.  **Refine Logging:** Ensure log messages (especially DEBUG) are informative and consistent across different components. Consider adding more context (like agent name) to log messages where appropriate.

**C. Web UI / UX Enhancements:**

6.  **Agent Rename:** Implement the backend logic (Redis RENAME, set updates) and UI flow to allow renaming an agent definition.
7.  **Agent List Filtering/Sorting:** Add UI elements to filter the agent list (e.g., by name, running status) or sort by different columns.
8.  **Tool Management Feedback:** Provide clearer visual feedback when tools are successfully added/removed via the inline editor (perhaps a temporary success message).
9.  **Configuration via ENV:** Make Redis connection details and the `AVAILABLE_MODELS` list configurable via environment variables instead of being hardcoded in `app.rb`.

**D. Architecture & Scalability:**

10. **Background Agent Execution:** The current `@agents` hash holds running agents *only* in the web server process memory. For any real deployment or scaling, this needs to change.
    *   **Implement:** Integrate a background job system (like Sidekiq, GoodJob, SolidQueue) using Redis or a database.
    *   **Change:** "Start Agent" would enqueue a background job. "Stop Agent" would signal the job to terminate. The UI would query the job system/Redis for agent status instead of the in-memory `@agents` hash. This is a significant architectural change.

