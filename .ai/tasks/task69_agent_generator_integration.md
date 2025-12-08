---
id: 69
title: 'Agent Generator Page Integration'
status: pending
priority: high
feature: AI Code Generator
dependencies:
  - 66
  - 68
assigned_agent: null
created_at: "2025-12-08T17:37:28Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Integrate the agent generator modal into the agents list page and wire up all components for a complete user experience.

## Details

- Update `lib/adk/web/views/agents.slim`:
  - Add "Generate with AI" button near "Create New Agent Definition"
  - Button styling to stand out but complement existing UI
  - Include the modal partial at the end of the page
  
- Button placement options (choose best fit):
  - Option A: Inside the "Create New Agent Definition" details as a secondary action
  - Option B: As a separate button next to the details summary
  - Option C: In the "Defined Agents" box header next to "Refresh List"

- Add required JavaScript:
  - Modal open/close handlers
  - Form submission via HTMX or fetch
  - Response handling (success/error)
  - CodeMirror initialization after content loads
  
- Update `lib/adk/web/app.rb`:
  - Register the new `AgentGeneratorRoutes` module
  - Ensure proper route ordering

- Add any required CSS to `main.scss`:
  - Modal backdrop styling
  - Transition animations
  - Code preview container styling

## Test Strategy

- Test button is visible and clickable on agents page
- Test modal opens when button is clicked
- Test full flow: describe → generate → preview → copy/download
- Test modal can be closed at any point
- Test keyboard accessibility (Escape to close, Tab navigation)
- Test responsive behavior on different screen sizes
