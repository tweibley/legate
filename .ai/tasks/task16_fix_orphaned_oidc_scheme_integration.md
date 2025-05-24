---
id: 16
title: 'Fix Orphaned OIDC Scheme Integration'
status: pending
priority: critical
feature: Authentication Scheme Cleanup
dependencies:
  - 4
  - 5
  - 6
assigned_agent: null
created_at: "2025-05-24T02:04:53Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Integrate the orphaned OIDC authentication scheme into the main schemes loader and ensure all references work consistently.

## Details

- The `lib/adk/auth/schemes/oidc.rb` file defines an `OIDC` class but it's not loaded by the main `schemes.rb` file
- Many examples, tests, and library files reference `ADK::Auth::Schemes::OIDC` but the main loader only includes `OpenIDConnect`
- There are currently two different OIDC implementations:
  - `OIDC` (in oidc.rb) - scheme_type is `:oidc`, simpler implementation
  - `OpenIDConnect` (in openid_connect.rb) - scheme_type is `:openid_connect`, more complex implementation with discovery
- Determine which implementation should be canonical and ensure consistent usage
- Update the main schemes loader to include the chosen implementation
- Ensure the credential system supports the correct auth_type
- Update the authentication manager to register the correct scheme
- Fix any references in middleware factory, coordinators, and other integration points

## Test Strategy

- Verify that examples using OIDC authentication (like `examples/auth/oidc_auth.rb`) run without modification
- Ensure tests exist and pass for the chosen OIDC scheme implementation
- Verify that the scheme can be created through the schemes factory
- Test that the authentication manager properly registers the OIDC scheme
- Confirm that credentials with `:oidc` auth_type work correctly with the scheme 