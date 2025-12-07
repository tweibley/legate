---
id: 62
title: 'Header Layout Consolidation'
status: completed
priority: high
feature: Agent Header Improvements
dependencies: []
assigned_agent: null
created_at: "2025-12-07T18:40:00Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Streamline the agent header by putting the status badge and action button on the same row, and integrating the description into the main header box.

## Details

- **Status/Action Row**:
  - Move status badge (Running/Stopped) and Start/Stop button to same horizontal line
  - Status on left, button on right within the row
  - Reduce overall header vertical height
  
- **Integrate Description**:
  - Move the agent description inside the `.agent-header-hero` box
  - Position it below the name/badges but above the stats
  - Keep the edit pencil icon visible
  - Support for empty/missing descriptions
  
- **Layout Structure**:
  ```
  ┌──────────────────────────────────────────────────────────────┐
  │  Agent Name                    [● Status] [Action Button]   │
  │  model-badge · type-badge                                   │
  │                                                              │
  │  "Description text here..."                           ✏️    │
  └──────────────────────────────────────────────────────────────┘
  ```

- **Files to Modify**:
  - `lib/adk/web/views/_display_agent_name.slim` - Integrate description
  - `lib/adk/web/views/_agent_status_controls.slim` - Horizontal layout
  - `lib/adk/web/views/agent.slim` - Remove separate description section
  - `lib/adk/web/public/styles/main.scss` - New layout styles

## Test Strategy

1. Navigate to agent details page
2. Verify header is more compact
3. Verify status and action button are on same row
4. Verify description is inside the header box
5. Test in both light and dark modes
6. Test with long agent names and descriptions
7. Test with agents that have no description


