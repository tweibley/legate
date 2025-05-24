---
id: 21
title: 'Complete Test Coverage for All Schemes'
status: inprogress
priority: high
feature: Authentication Scheme Cleanup
dependencies:
  - 16
  - 17
  - 18
assigned_agent: claude
created_at: "2025-05-24T02:04:53Z"
started_at: "2025-05-24T03:15:06Z"
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

## Agent Notes

### Phase 1: Current State Analysis (Completed)

**Available Schemes (from lib/adk/auth/schemes.rb):**
1. ✅ `api_key` → `ApiKey`
2. ✅ `http_bearer` → `HTTPBearer`  
3. ✅ `oauth2` → `OAuth2`
4. ✅ `oidc`, `openid_connect` → `OpenIDConnect`
5. ✅ `service_account` → `ServiceAccount`
6. ✅ `google_service_account` → `GoogleServiceAccount`

**Current Test Files (from spec/adk/auth/schemes/):**
1. ✅ `api_key_spec.rb` - Tests ApiKey scheme
2. ✅ `http_bearer_spec.rb` - Tests HTTPBearer scheme
3. ✅ `oauth2_spec.rb` - Tests OAuth2 scheme (comprehensive)
4. ✅ `oauth2_with_mock_spec.rb` - Tests OAuth2 with mock server
5. ✅ `openid_connect_spec.rb` - Tests OpenIDConnect scheme (comprehensive)
6. ✅ `openid_connect_with_mock_spec.rb` - Tests OIDC with mock server
7. ✅ `service_account_spec.rb` - Tests ServiceAccount scheme
8. ✅ `service_account_with_mock_spec.rb` - Tests ServiceAccount with mock
9. ✅ `google_service_account_spec.rb` - Tests GoogleServiceAccount scheme

**Initial Assessment:**
- ✅ **Complete Coverage**: All 6 schemes have corresponding test files
- ✅ **No Orphaned Tests**: No tests found for deprecated/removed schemes
- ✅ **Comprehensive Testing**: Both unit and integration tests with mock servers
- ⚠️ **Need to Verify**: Test quality, factory integration, manager integration

### Phase 2: Test Quality Analysis (Starting)

**Areas to Verify:**
1. All schemes can be created through factory
2. All schemes work with authentication manager
3. Test naming and structure consistency
4. Coverage of all scheme methods and functionality
5. Integration testing with middleware and coordinators
6. Error handling and edge cases 