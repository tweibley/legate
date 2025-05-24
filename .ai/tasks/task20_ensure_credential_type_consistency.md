---
id: 20
title: 'Ensure Credential Type Consistency'
status: pending
priority: high
feature: Authentication Scheme Cleanup
dependencies:
  - 16
  - 17
  - 18
assigned_agent: null
created_at: "2025-05-24T02:04:53Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Align credential auth_types with actually available schemes and fix any mismatches between credential types and scheme availability.

## Details

- The `Credential` class defines valid types including `:oidc` but the main schemes loader may not support the OIDC scheme
- Some credential types may reference unavailable or orphaned schemes
- Need to ensure all credential `auth_type` values have corresponding loaded schemes
- Update the `VALID_TYPES` constant in the Credential class to match actually available schemes
- Ensure the required attributes validation aligns with the chosen scheme implementations
- Fix any credential validation logic that references deprecated or unavailable schemes
- Update error messages to clearly indicate available credential types
- Ensure credential-to-scheme compatibility checking works correctly

## Test Strategy

- Test that all credential auth_types can successfully create instances of their corresponding schemes
- Verify that credential validation works correctly for all supported types
- Ensure error messages for invalid credential types are accurate and helpful
- Test that all credential types work correctly with the authentication manager
- Confirm that no configuration errors occur due to credential type mismatches 