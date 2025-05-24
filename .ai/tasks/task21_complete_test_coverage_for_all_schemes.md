---
id: 21
title: 'Complete Test Coverage for All Schemes'
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

Add comprehensive tests for all authentication schemes that should be available and remove tests for deprecated schemes.

## Details

- Currently missing tests for some schemes (like the orphaned OIDC scheme)
- Need to ensure all schemes loaded by the main schemes.rb have corresponding test files
- Remove any tests for schemes that are being deprecated or removed
- Ensure consistent test naming and structure patterns across all scheme tests
- Add tests for scheme loading through the schemes factory
- Test authentication manager registration for all schemes
- Verify that all scheme integration points (middleware, coordinators) are tested
- Ensure test coverage includes both unit tests and integration tests for each scheme

## Test Strategy

- Verify that test files exist for all schemes loaded by the main schemes loader
- Ensure no test files exist for orphaned or deprecated schemes
- Run all authentication scheme tests and verify they pass
- Check test coverage reports to ensure comprehensive coverage of all scheme functionality
- Test that all schemes can be created through the factory and work with the authentication manager 