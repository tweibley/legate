---
id: 61
title: 'Tools Tab Card Grid Layout'
status: pending
priority: low
feature: Agent Details UI Polish
dependencies:
  - 59
assigned_agent: null
created_at: "2025-12-07T15:24:52Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Convert the Tools tab from a table layout to a card grid for better visual scanning and a more modern appearance.

## Details

- **Card Grid Layout**:
  - Replace table with responsive card grid
  - 2-3 cards per row on desktop, 1 on mobile
  - Consistent card heights within rows
  
- **Card Content**:
  - Tool icon (generic `fa-wrench` or tool-specific if available)
  - Tool name as card title
  - Truncated description (2-3 lines)
  - "View Details" link on hover or always visible
  
- **Hover Interactions**:
  - Subtle lift/shadow on hover
  - Reveal full description or action buttons
  
- **Empty State**:
  - Friendly message when no tools configured
  - Link to add tools
  
- **Files to Modify**:
  - `lib/adk/web/views/_agent_tool_table.slim` - Convert to card layout
  - `lib/adk/web/public/styles/main.scss` - Tool card styling

## Test Strategy

1. Navigate to agent details Tools tab
2. Verify tools display as card grid
3. Verify cards show icon, name, description
4. Test hover interactions
5. Test responsive layout at different widths
6. Test empty state with agent that has no tools
7. Test in both light and dark modes

