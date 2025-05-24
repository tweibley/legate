---
id: 17
title: 'Resolve Bearer Token Implementation Duplication'
status: pending
priority: high
feature: Authentication Scheme Cleanup
dependencies:
  - 4
assigned_agent: null
created_at: "2025-05-24T02:04:53Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Choose a canonical Bearer token implementation, remove duplicates, and ensure consistent interfaces across the authentication system.

## Details

- There are currently two separate Bearer token implementations:
  - `Bearer` (in bearer.rb) - scheme_type is `:bearer`, stores token as `bearer_token` in ExchangedCredential
  - `HTTPBearer` (in http_bearer.rb) - scheme_type is `:http_bearer`, stores token as `access_token` in ExchangedCredential
- The `http_bearer.rb` file requires `bearer.rb` but doesn't use it, indicating duplication
- The main `schemes.rb` only loads `HTTPBearer`, making `Bearer` orphaned
- Different interfaces for essentially the same functionality create confusion
- Need to choose one implementation and deprecate the other
- Ensure consistent token storage field names across the chosen implementation
- Remove the orphaned implementation and any unused code
- Update any references to use the canonical implementation

## Test Strategy

- Verify that Bearer token authentication works consistently through the chosen implementation
- Ensure all Bearer token tests pass with the canonical implementation
- Confirm that no "class not found" errors occur for documented Bearer token usage
- Test that Bearer tokens are stored consistently in ExchangedCredentials
- Verify that Bearer token middleware works correctly with the chosen implementation 