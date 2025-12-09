# PRD: Agent Status Persistence Fix

## 1. Product overview

### 1.1 Document title and version

- PRD: Agent Status Persistence Fix
- Version: 1.0

### 1.2 Product summary

When the ADK web server is stopped (via Ctrl+C or kill), agents stop running because they exist in-memory within the same Ruby process. However, the `persistent_status` field in Redis remains set to 'running', causing the UI to display agents as "Running" when the server restarts, even though the agents haven't been restarted.

The current `synchronize_persistent_agents` method in the web app's initialization is designed to handle this by restarting agents that have `persistent_status == 'running'`. However, this mechanism can fail silently due to the use of Sinatra's `halt` method in `_start_agent`, which is designed for request contexts, not initialization contexts.

This plan addresses the issue by implementing two fixes:
1. Replace the `halt` call with proper error handling that works in any context
2. Reset all `persistent_status` values to 'stopped' on startup before attempting any synchronization, ensuring the UI accurately reflects actual agent state

## 2. Goals

### 2.1 Business goals

- Ensure the web UI accurately reflects the actual state of agents
- Improve developer experience by preventing confusion about agent status
- Maintain data integrity between in-memory agent state and persisted state

### 2.2 User goals

- See accurate agent status in the UI at all times
- Trust that "Running" means the agent is actually operational
- Not have to manually restart agents after server restarts

### 2.3 Non-goals

- Implementing graceful shutdown handlers (can be a future enhancement)
- Auto-starting agents based on a new configuration flag (can be a future enhancement)
- Distributed agent state synchronization across multiple server instances

## 3. User personas

### 3.1 Key user types

- ADK Developer: Uses the web UI to manage agents during local development

### 3.2 Basic persona details

- **ADK Developer**: Runs the web server locally, expects agents to show accurate status, frequently restarts the server during development

### 3.3 Role-based access

- **Developer**: Full access to agent management, start/stop agents, view status

## 4. Functional requirements

- **Fix halt usage in _start_agent** (Priority: High)
  - Replace Sinatra `halt` call with proper error handling
  - Return `nil` and log error when definition store is unavailable
  - Ensure method works correctly in both request and initialization contexts

- **Reset persistent_status on startup** (Priority: High)
  - On server startup, reset all agents with `persistent_status == 'running'` to 'stopped'
  - Log each reset for debugging purposes
  - Do this BEFORE any synchronization attempts
  - This ensures UI accurately reflects reality since nothing is actually running at boot time

## 5. User experience

### 5.1 Entry points & first-time user flow

- User starts the web server via `bundle exec adk web start`
- All agents show as "Stopped" initially (accurate)
- User can start agents as needed

### 5.2 Core experience

- **Server restart**: User stops server (Ctrl+C), restarts it
  - All agents automatically show "Stopped" (accurate state)
  - No stale "Running" indicators
- **Manual agent management**: User starts/stops agents via UI
  - Status updates persist correctly to Redis
  - UI reflects actual state

### 5.3 Advanced features & edge cases

- Force kill of server (kill -9): Status still resets on next startup
- Redis connection issues: Graceful handling with appropriate logging
- Multiple agents with stale status: All reset correctly

### 5.4 UI/UX highlights

- Status badges accurately reflect agent state
- No misleading "Running" indicators after server restart

## 6. Narrative

A developer runs ADK locally, starts several agents via the web UI, and then stops the server to make code changes. When they restart the server, they see all agents correctly showing "Stopped" status. They can now start whichever agents they need for their current testing. The UI always shows the truth about what's running.

## 7. Success metrics

### 7.1 User-centric metrics

- Zero instances of stale "Running" status after server restart
- Agent status always matches actual runtime state

### 7.2 Business metrics

- Reduced developer confusion and support questions about agent status

### 7.3 Technical metrics

- No silent failures during agent synchronization
- Proper error logging for debugging

## 8. Technical considerations

### 8.1 Integration points

- `lib/adk/web/app.rb`: Main web application with `_start_agent` and `synchronize_persistent_agents`
- `lib/adk/definition_store/redis_store.rb`: Redis-backed persistence for agent definitions
- Redis: External storage for `persistent_status` field

### 8.2 Data storage & privacy

- Agent status is stored in Redis
- No sensitive data involved in this change

### 8.3 Scalability & performance

- Startup performance impact is minimal (one Redis call per agent to reset status)
- No impact on runtime performance

### 8.4 Potential challenges

- Must ensure error handling doesn't mask real issues
- Need to preserve logging for debugging

## 9. Milestones & sequencing

### 9.1 Project estimate

- Small: 1-2 hours

### 9.2 Team size & composition

- 1 developer

### 9.3 Suggested phases

- **Phase 1**: Implement both fixes (30-60 minutes)
  - Key deliverables: Updated `_start_agent`, updated `synchronize_persistent_agents`
- **Phase 2**: Testing (15-30 minutes)
  - Key deliverables: Manual testing of server restart scenarios

## 10. User stories

### 10.1 Accurate status after restart

- **ID**: US-001
- **Description**: As a developer, I want agents to show accurate "Stopped" status after I restart the server so that I'm not confused about what's actually running.
- **Acceptance Criteria**:
  - Start server, start an agent, verify "Running" status
  - Stop server (Ctrl+C), restart server
  - Agent shows "Stopped" status (not stale "Running")
  - Can successfully start the agent again

### 10.2 No silent failures

- **ID**: US-002
- **Description**: As a developer, I want proper error logging if something fails during startup so that I can debug issues.
- **Acceptance Criteria**:
  - If definition store is unavailable during `_start_agent`, error is logged (not silently swallowed)
  - Log messages indicate status resets on startup

