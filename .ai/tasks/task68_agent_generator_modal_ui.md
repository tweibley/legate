---
id: 68
title: 'Agent Generator Modal UI'
status: pending
priority: high
feature: AI Code Generator
dependencies:
  - 66
assigned_agent: null
created_at: "2025-12-08T17:37:28Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Create the modal UI component for the agent generator, including the input form, code preview with syntax highlighting, and export actions.

## Details

- Create new partial `lib/adk/web/views/_agent_generator_modal.slim`
- Modal structure:
  
  **Header:**
  - Title: "Generate Agent with AI"
  - Close button (X)
  
  **Input Section:**
  - Large textarea for natural language description
  - Placeholder examples:
    - "Create an agent that summarizes customer feedback and identifies key themes"
    - "Create a sequential workflow that first researches a topic, then writes an article"
    - "Create a webhook agent that receives GitHub events and logs them"
  - "Generate" button with loading state
  
  **Output Section (hidden until generation):**
  - CodeMirror editor with Ruby syntax highlighting
  - Read-only mode for preview
  - Uses existing CodeMirror theme integration
  
  **Action Buttons:**
  - "Copy to Clipboard" button with icon
  - "Download as .rb" button with icon
  - "Regenerate" button to try again
  - "Close" button
  
  **States:**
  - Initial: Input visible, output hidden
  - Loading: Spinner on generate button, disabled inputs
  - Success: Output section visible with code
  - Error: Error notification with message

- Add JavaScript for:
  - Copy to clipboard functionality
  - Download as file functionality
  - CodeMirror initialization for output
  - HTMX integration for form submission

- Style to match existing modal patterns in the UI

## Test Strategy

- Test modal opens and closes correctly
- Test form validation (empty input)
- Test loading state displays during generation
- Test copy to clipboard works
- Test download creates valid .rb file
- Test CodeMirror displays Ruby code correctly
- Test modal works in both light and dark mode
