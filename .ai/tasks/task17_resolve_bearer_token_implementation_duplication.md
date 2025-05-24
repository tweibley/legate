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

Based on git history analysis, the duplication occurred as follows:
- `HTTPBearer` was created first in the core authentication infrastructure
- `Bearer` was created later as an improved copy to fix bugs with request handling
- `Bearer` includes important fixes: deep copying requests, better Excon stack handling
- However, `Bearer` was never integrated into the main schemes loader, making it orphaned

**Current state:**
- `HTTPBearer` (in http_bearer.rb) - scheme_type `:http_bearer`, stores as `access_token`, widely used but has bugs
- `Bearer` (in bearer.rb) - scheme_type `:bearer`, stores as `bearer_token`, has bug fixes but orphaned
- Main `schemes.rb` only loads `HTTPBearer`, making `Bearer` unreachable
- `http_bearer.rb` requires `bearer.rb` but doesn't use it

**Resolution strategy:**
- Merge the bug fixes from `Bearer` into `HTTPBearer` 
- Keep `HTTPBearer` as the canonical implementation (widely used, properly loaded)
- Remove the orphaned `Bearer` class and file
- Ensure consistent token storage and interfaces
- Update any references to use the improved `HTTPBearer`

## Test Strategy

- Verify that the improved `HTTPBearer` implementation handles request copying correctly
- Ensure all existing HTTP Bearer token tests continue to pass
- Test that the bug fixes from `Bearer` are properly integrated (deep copying, Excon stack handling)
- Confirm that Bearer tokens work correctly with middleware and don't modify original requests
- Verify that `HTTPBearer` maintains backward compatibility with existing usage patterns
- Test that removing the orphaned `Bearer` class doesn't break any existing functionality 