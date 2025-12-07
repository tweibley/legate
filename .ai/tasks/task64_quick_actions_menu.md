---
id: 64
title: 'Quick Actions Menu'
status: completed
priority: medium
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

Add an overflow menu ("...") in the header providing quick access to common agent actions like Edit, Duplicate, Export, and Delete.

## Details

- **Menu Button**:
  - "⋮" (vertical ellipsis) icon button
  - Positioned after the Start/Stop button
  - Subtle styling that doesn't compete with main action
  
- **Menu Items**:
  - **Edit Agent**: Opens agent configuration (Config tab)
  - **Duplicate**: Creates a copy of the agent with "Copy of {name}"
  - **Export JSON**: Downloads agent configuration as JSON file
  - Divider
  - **Delete Agent**: Removes agent (with confirmation)

- **Behavior**:
  - Click outside menu closes it
  - Delete shows confirmation modal/dialog
  - Duplicate creates agent and navigates to it
  - Export triggers browser download

- **Visual Design**:
  - Dropdown menu with icons for each action
  - Delete action in red/danger color
  - Smooth fade-in animation

- **Files to Modify**:
  - `lib/adk/web/views/_agent_status_controls.slim` - Add menu button
  - `lib/adk/web/views/agent.slim` - Add menu dropdown markup
  - `lib/adk/web/public/styles/main.scss` - Dropdown styling
  - May need new routes for duplicate/export functionality

## Test Strategy

1. Click "..." button and verify menu appears
2. Click outside menu and verify it closes
3. Test each menu action
4. Verify delete shows confirmation
5. Test keyboard accessibility (Escape to close)
6. Test in both light and dark modes


