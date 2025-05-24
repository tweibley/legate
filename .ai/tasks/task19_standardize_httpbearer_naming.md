---
id: 19
title: 'Standardize HTTPBearer Naming'
status: pending
priority: medium
feature: Authentication Scheme Cleanup
dependencies:
  - 17
assigned_agent: null
created_at: "2025-05-24T02:04:53Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Standardize all references to use consistent class names (HTTPBearer vs HttpBearer) across the codebase.

## Details

- There are inconsistent references to both `ADK::Auth::Schemes::HTTPBearer` and `ADK::Auth::Schemes::HttpBearer`
- The `http_bearer.rb` file defines `HTTPBearer` and creates an alias `HttpBearer = HTTPBearer`
- Different files use different casing which creates confusion
- Need to choose one canonical naming convention and update all references
- Update all examples, documentation, tests, and library code to use consistent naming
- Consider removing the alias if it's not needed for backward compatibility
- Ensure all documentation uses the canonical class name
- Update any API reference documentation to match the chosen naming convention

## Test Strategy

- Search the entire codebase for both naming variants and verify all are updated consistently
- Ensure all tests pass with the standardized naming
- Verify that examples and documentation run/work correctly with the canonical naming
- Confirm that no "class not found" errors occur due to naming inconsistencies
- Test that middleware factory and other integration points use the correct class name 