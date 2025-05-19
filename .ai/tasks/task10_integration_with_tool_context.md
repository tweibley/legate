---
id: 10
title: 'Integration with Tool Context'
status: pending
priority: high
feature: Authentication System
dependencies:
  - 1
  - 9
assigned_agent: null
created_at: "2025-05-19T16:41:55Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Enhance the ToolContext with authentication methods for tool-side handling.

## Details

- Enhance or create the `Adk::ToolContext` class:
  - Add access to the mutable `ADK::Session` object
  - Create methods for authentication operations
  - Implement consistent error handling
- Implement authentication helper methods:
  - Add `get_auth_response(scheme, credential)` method to check for completed interactive flows
  - Implement `request_credential(auth_config)` method to initiate interactive flows
  - Create `get_configured_credential(type)` method to retrieve initial configuration
  - Add `get_cached_credential(cache_key)` method for retrieving cached tokens
- Create token management utilities:
  - Implement methods to store tokens securely in the session state
  - Add utilities to decrypt and validate cached tokens
  - Create helpers for token refresh
  - Implement token invalidation methods
- Add error handling and reporting:
  - Create consistent error types for authentication failures
  - Implement detailed error messages
  - Add logging for authentication operations
  - Create debug utilities for troubleshooting
- Update documentation and examples:
  - Create detailed documentation for the ToolContext authentication methods
  - Add examples of authentication usage in custom tools
  - Implement best practices for secure authentication

## Test Strategy

- Write unit tests for the ToolContext authentication methods
- Test integration with session state
- Verify token caching and retrieval works correctly
- Test error handling and reporting
- Create integration tests with mock authentication flows 