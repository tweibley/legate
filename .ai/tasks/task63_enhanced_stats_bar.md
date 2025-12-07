---
id: 63
title: 'Enhanced Stats Bar'
status: completed
priority: high
feature: Agent Header Improvements
dependencies:
  - 62
assigned_agent: null
created_at: "2025-12-07T18:40:00Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Add a horizontal stats bar at the bottom of the header showing useful metrics like tool count, last run time, and current status.

## Details

- **Stats Bar Layout**:
  ```
  ┌──────────────────────────────────────────────────────────────┐
  │  🔧 1 Tool      │      ⏱️ Last: 2m ago      │      ✅ Active │
  └──────────────────────────────────────────────────────────────┘
  ```

- **Stat Items**:
  - **Tool Count**: Number icon + count + "Tool(s)" label
    - Clickable - navigates to Tools tab
    - Shows "0 Tools" if none configured
  - **Last Run**: Clock icon + relative timestamp
    - Shows "Never" if agent hasn't run
    - Can use placeholder "N/A" initially if timestamp not available
  - **Status**: Check/pause icon + "Active" or "Idle"
    - Green check for running, gray pause for stopped
    - Matches the main status badge

- **Visual Design**:
  - Horizontal dividers between stat items
  - Subtle background differentiation from main header
  - Icons in muted color, values in primary color
  - Responsive: stack vertically on mobile

- **Files to Modify**:
  - `lib/adk/web/views/_agent_status_controls.slim` - Add stats bar
  - `lib/adk/web/public/styles/main.scss` - Stats bar styling

## Test Strategy

1. Verify stats bar displays below header
2. Click tool count and verify navigation to Tools tab
3. Verify proper pluralization ("1 Tool" vs "2 Tools")
4. Test in light and dark modes
5. Test responsiveness on narrow screens


