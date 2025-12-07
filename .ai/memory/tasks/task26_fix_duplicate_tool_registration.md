---
id: 26
title: 'Fix Duplicate Tool Registration Bug'
status: completed
priority: critical
feature: Web UI Bug Fixes
dependencies: []
assigned_agent: null
created_at: "2025-12-05T05:21:43Z"
started_at: "2025-12-05T05:24:51Z"
completed_at: "2025-12-05T05:29:53Z"
error_log: null
---

## Description

Fix the bug where tools are registered twice with different names (e.g., `random_number_tool` AND `random_number`). The root cause is that `Tool.inherited` runs before class body executes, so explicit_tool_name is not yet set during initial registration.

## Details

### Root Cause Analysis

The `Tool.inherited` hook in `lib/adk/tool.rb` is called when a tool class is **defined**, but this happens BEFORE the class body executes:

1. When `RandomNumberTool` class definition starts, `inherited` is called
2. At this point, `explicit_tool_name` is still `nil`
3. Tool is registered under the inferred name: `random_number_tool`
4. Class body executes, sets `explicit_tool_name = :random_number`
5. Later in `lib/adk.rb`, explicit registration adds the tool again with name: `random_number`

### Evidence from logs

```
DEBUG: Tool subclass ADK::Tools::RandomNumberTool inherited. Attempting registration.
DEBUG: GlobalToolManager: Registered tool 'random_number_tool' with class ADK::Tools::RandomNumberTool.
...
DEBUG: GlobalToolManager: Registered tool 'random_number' with class ADK::Tools::RandomNumberTool.
```

### Affected Tools

These tools appear twice with different names:
- `random_number_tool` / `random_number` (RandomNumberTool)
- `agent_tool` / `delegate_task` (AgentTool)
- `check_job_status_tool` / `check_job_status` (CheckJobStatusTool)
- `sleepy_tool` / `start_sleepy_job` (SleepyTool)

### Solution Approach

**Option A (Recommended): Remove automatic registration from `inherited` hook**

1. Remove the `GlobalToolManager.register_tool(subclass)` call from `Tool.inherited`
2. Tools are already explicitly registered in `lib/adk.rb` - this becomes the only registration point
3. Ensure all built-in tools are listed in the explicit registration block
4. Add a note that custom tools should either:
   - Use `GlobalToolManager.register_tool(MyTool)` explicitly
   - Or be discovered via tool paths when creating agents

**Option B: Defer registration using TracePoint**

Use Ruby's TracePoint to detect when the class definition is complete and only then register. This is more complex but allows auto-registration to work correctly.

### Files to Modify

- `lib/adk/tool.rb` - Remove or modify the `inherited` hook
- `lib/adk.rb` - Ensure explicit registration is complete and remove duplicate tool entries
- `lib/adk/global_tool_manager.rb` - Potentially add a `deregister_tool` method for cleanup

### Backward Compatibility

- Tools using the old `define_metadata` API should continue to work
- Tools using the new DSL (`explicit_tool_name`, `tool_description`) should work
- Custom tools should still be discoverable via tool paths

## Test Strategy

1. Start the web UI: `bundle exec adk web start`
2. Navigate to http://localhost:4567/tools
3. Verify each tool appears only ONCE
4. Navigate to http://localhost:4567/agents
5. Click "Create New Agent Definition"
6. Verify the tools checkbox list shows no duplicates
7. Check server logs for duplicate registration warnings
8. Run existing tool tests: `bundle exec rspec spec/adk/tools/`
9. Run global tool manager tests: `bundle exec rspec spec/adk/global_tool_manager_spec.rb`

