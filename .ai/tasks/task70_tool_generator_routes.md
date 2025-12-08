---
id: 70
title: 'Tool Generator Backend Routes'
status: pending
priority: high
feature: AI Code Generator
dependencies: []
assigned_agent: null
created_at: "2025-12-08T17:48:07Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Create the backend route for the AI-powered tool generator feature. This includes the POST endpoint that accepts natural language descriptions and returns generated Ruby tool class code using Gemini AI.

## Details

- Add to existing routes or create new file `lib/adk/web/routes/tool_generator_routes.rb`
- Implement `POST /tools/generate` endpoint that:
  - Accepts JSON body with `description` field
  - Validates input (non-empty, reasonable length)
  - Builds comprehensive tool-specific system prompt (see Task 71)
  - Calls Gemini API using existing pattern
  - Extracts and cleans generated code (strip markdown fences)
  - Returns JSON: `{ code: "...", suggested_name: "...", tool_type: "simple|http|async" }`
- Handle errors gracefully:
  - Missing API key → 503 with clear message
  - Empty description → 400 with validation error
  - Gemini API errors → 500 with user-friendly message
- Register the routes module in `app.rb` if separate file

## Test Strategy

- Test endpoint with various tool descriptions:
  - Simple tool ("Create a tool that calculates BMI")
  - HTTP tool ("Create a tool that fetches weather from OpenWeather API")
  - Async tool ("Create a tool that processes large CSV files in background")
- Verify generated code is syntactically valid Ruby
- Test error cases (empty input, missing API key)
- Verify response format is correct JSON

