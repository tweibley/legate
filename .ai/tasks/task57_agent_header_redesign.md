---
id: 57
title: 'Agent Details Header Redesign'
status: completed
priority: high
feature: Agent Details UI Polish
dependencies: []
assigned_agent: null
created_at: "2025-12-07T15:24:52Z"
started_at: "2025-12-07T15:27:28Z"
completed_at: "2025-12-07T15:33:46Z"
error_log: null
---

## Description

Redesign the agent details header to create a "hero profile" style with prominent status controls, key metrics, and improved visual hierarchy.

## Details

- **Header Layout Changes**:
  - Display agent name as large heading (h1 or equivalent styling)
  - Add model badge (e.g., `gemini-2.0-flash`) next to name
  - Add type badge (LLM, Sequential, Parallel, Loop) next to name
  - Move Start/Stop buttons to prominent, larger buttons on the right
  
- **Quick Stats Row**:
  - Add a stats row below the name showing:
    - Tool count (e.g., "3 Tools")
    - Last run time (if available)
    - Uptime (if running)
  
- **Consolidate Sections**:
  - Remove or collapse Agent Type section (info now in badge)
  - Remove or collapse Agent Hierarchy section (move to collapsible or Config tab)
  - Keep description inline with edit button
  
- **Files to Modify**:
  - `lib/adk/web/views/agent.slim` - Header structure
  - `lib/adk/web/views/_display_agent_name.slim` - Name display partial
  - `lib/adk/web/views/_agent_status_controls.slim` - Status controls partial
  - `lib/adk/web/public/styles/main.scss` - Header CSS

## Test Strategy

1. Navigate to `/agents/{agent-name}` in browser
2. Verify header displays name, model badge, and type badge
3. Verify Start/Stop buttons are large and prominent
4. Verify quick stats row shows tool count
5. Test in both light and dark modes
6. Test with running and stopped agent states

