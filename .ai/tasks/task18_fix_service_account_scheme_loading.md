---
id: 18
title: 'Fix Service Account Scheme Loading'
status: pending
priority: high
feature: Authentication Scheme Cleanup
dependencies:
  - 7
assigned_agent: null
created_at: "2025-05-24T02:04:53Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Properly integrate both ServiceAccount and GoogleServiceAccount schemes into the main schemes loader to make them available through the standard factory.

## Details

- The main `schemes.rb` file doesn't load or include either `ServiceAccount` or `GoogleServiceAccount` schemes
- Both schemes are widely used and referenced throughout the codebase (examples, tests, documentation)
- The authentication manager tries to register a `ServiceAccount` scheme but it's not loaded properly
- The `GoogleServiceAccount` is a proper specialization of `ServiceAccount` and should be available
- Both schemes should be accessible through the schemes factory
- Need to add proper requires to the main schemes loader
- Update the schemes factory to support creating both service account types
- Ensure the authentication manager can register both schemes
- Verify credential types properly support both service account types

## Test Strategy

- Verify that both `ServiceAccount` and `GoogleServiceAccount` can be instantiated through the schemes factory
- Ensure service account examples (like `examples/auth/service_account.rb`) run without modification
- Test that the authentication manager properly registers both service account schemes
- Confirm that credentials with `:service_account` and `:google_service_account` auth_types work correctly
- Verify that all service account tests pass with the properly loaded schemes 