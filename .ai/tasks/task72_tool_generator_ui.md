---
id: 72
title: 'Tool Generator Modal UI & Integration'
status: pending
priority: high
feature: AI Code Generator
dependencies:
  - 70
  - 71
assigned_agent: null
created_at: "2025-12-08T17:48:07Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Create the modal UI for the tool generator on the Tools page, including input form, code preview with syntax highlighting, and export actions.

## Details

- Create new partial `lib/adk/web/views/_tool_generator_modal.slim`
  - Can share structure with agent generator modal (consider extracting common partial)
  
- Modal structure:
  
  **Header:**
  - Title: "Generate Tool with AI"
  - Close button (X)
  
  **Input Section:**
  - Large textarea for natural language description
  - Placeholder examples:
    - "Create a tool that converts temperatures between Celsius and Fahrenheit"
    - "Create a tool that fetches stock prices from Alpha Vantage API"
    - "Create a tool that processes large CSV files in the background"
  - "Generate" button with loading state
  
  **Output Section (hidden until generation):**
  - CodeMirror editor with Ruby syntax highlighting
  - Read-only mode for preview
  - Badge showing detected tool type (Simple / HTTP / Async)
  
  **Action Buttons:**
  - "Copy to Clipboard" button with icon
  - "Download as .rb" button with icon
  - "Regenerate" button
  - "Close" button

- Update `lib/adk/web/views/tools.slim`:
  - Add "Generate with AI" button in the tools page header
  - Include the modal partial
  - Wire up JavaScript for modal open/close

- Add JavaScript for:
  - Copy to clipboard functionality
  - Download as file functionality  
  - CodeMirror initialization
  - HTMX integration for form submission

## Test Strategy

- Test modal opens from Tools page
- Test form validation (empty input)
- Test loading state displays during generation
- Test copy to clipboard works
- Test download creates valid .rb file with tool name
- Test CodeMirror displays Ruby code correctly
- Test tool type badge shows correct type
- Test modal works in both light and dark mode

