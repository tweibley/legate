# Potential Next Steps for MCP Server Example

Based on the discussion after successfully implementing the multi-tool agent and resource exposure (`examples/adk_mcp_server_resource_example.rb`), here are some potential directions for further development:

1.  **Explore Asynchronous Operations:**
    *   Model background jobs (like those initiated by `SleepyTool`) more explicitly within MCP.
    *   Create a `/jobs` resource to list active/completed jobs.
    *   Create a `/jobs/{job_id}` resource to view status/results, linking to `CheckJobStatusTool` functionality.
    *   Requires deeper integration with ADK's async handling (Sidekiq) and representing job state via MCP resources.

2.  **Add More Custom Tools/Resources:**
    *   Invent new simple ADK tools (e.g., `WordCounterTool`, simple key-value store).
    *   Decide how best to expose them via MCP:
        *   Only through the `master_agent`?
        *   As dedicated MCP tools?
        *   As MCP resources?

3.  **Refine Agent Interaction:**
    *   Experiment with diverse prompts for `run_agent_master_agent`.
    *   Analyze how well the agent chooses between tools (`calculator`, `cat_facts`, `echo`, etc.).
    *   If needed, refine tool descriptions or agent configuration (e.g., model parameters, planner settings) to improve tool selection.

4.  **Use the Delegate Tool:**
    *   Demonstrate the `delegate_task` tool (`ADK::Tools::AgentTool`).
    *   Requires setting up a *second* agent (potentially defined in the same script or run separately).
    *   Configure the `master_agent` to delegate specific tasks to this second agent.

5.  **Persistent Sessions:**
    *   Switch the `master_agent`'s session service from `ADK::SessionService::InMemory` to `ADK::SessionService::Redis`.
    *   Requires a running Redis instance.
    *   Demonstrates how agent conversational state can persist across multiple MCP calls/server restarts.

6.  **Code Cleanup/Refactoring:**
    *   Move the custom `FastMcp::Resource` and `FastMcp::Tool` definitions (`RandomNumberResource`, `CatFactResource`, etc.) from `examples/adk_mcp_server_resource_example.rb` into separate, well-named files under `examples/lib/` or similar.
    *   Update the main example script to require these external files. 