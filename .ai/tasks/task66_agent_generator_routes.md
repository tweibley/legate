---
id: 66
title: 'Agent Generator Backend Routes'
status: pending
priority: high
feature: AI Code Generator
dependencies: []
assigned_agent: null
created_at: "2025-12-08T17:37:28Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Create the backend route module for the AI-powered agent generator feature. This includes the POST endpoint that accepts natural language descriptions and returns generated Ruby agent definition code using Gemini AI.

## Details

- Create new file `lib/adk/web/routes/agent_generator_routes.rb`
- Implement `POST /agents/generate` endpoint that:
  - Accepts JSON body with `description` field
  - Validates input (non-empty, reasonable length)
  - Builds comprehensive system prompt (see Task 67)
  - Calls Gemini API using existing pattern from `agent_interaction_routes.rb`
  - Extracts and cleans generated code (strip markdown fences)
  - Returns JSON: `{ code: "...", suggested_name: "..." }`
- Handle errors gracefully:
  - Missing API key → 503 with clear message
  - Empty description → 400 with validation error
  - Gemini API errors → 500 with user-friendly message
- Register the routes module in `app.rb`

## Test Strategy

- Test endpoint with various agent descriptions:
  - Basic LLM agent ("Create an agent that summarizes documents")
  - Workflow agent ("Create a sequential workflow that...")
  - Agent with callbacks and advanced features
- Verify generated code is syntactically valid Ruby
- Test error cases (empty input, missing API key)
- Verify response format is correct JSON
