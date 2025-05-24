---
id: 22
title: 'Update Documentation and Examples'
status: inprogress
priority: medium
feature: Authentication Scheme Cleanup
dependencies:
  - 16
  - 17
  - 18
  - 19
  - 20
assigned_agent: claude
created_at: "2025-05-24T02:04:53Z"
started_at: "2025-05-24T03:23:03Z"
completed_at: null
error_log: null
---

## Description

Update all documentation and examples to reference only canonical, working authentication schemes with consistent naming.

## Details

- Many documentation files reference schemes that may not be properly loaded (like OIDC vs OpenIDConnect)
- Examples may use inconsistent class names or reference orphaned implementations
- API documentation needs to match the actual available classes and methods
- Update all authentication guides to use canonical scheme implementations
- Fix any examples that don't run due to scheme loading issues
- Ensure consistent class naming throughout all documentation
- Update troubleshooting guides to reflect the corrected scheme availability
- Verify that all code examples in documentation are functional

## Test Strategy

- Run all authentication examples to ensure they work without modification
- Verify that documentation references match actual available scheme classes
- Check that API documentation accurately reflects the implemented schemes
- Ensure all authentication guides contain working, tested code examples
- Confirm that no documentation references deprecated or unavailable schemes

## Agent Notes

### Phase 1: Documentation Analysis (Completed)

**Key Findings:**

**✅ Correct Documentation:**
- `public/docs/authentication/index.md` - Uses correct references
- `public/docs/authentication/guides/bearer.md` - Correctly references `Adk::Auth::Schemes::HTTPBearer`

**❌ Issues Found:**
1. **OIDC Class Name Issue**: `public/docs/authentication/api_reference/schemes/oidc.md` 
   - References `Adk::Auth::Schemes::Oidc` (incorrect)
   - Should reference `Adk::Auth::Schemes::OpenIDConnect` (correct)

2. **Duplicate Documentation**: Both `oidc.md` and `openid_connect.md` exist
   - Both document the same scheme class (`OpenIDConnect`)
   - `:oidc` and `:openid_connect` both map to `ADK::Auth::Schemes::OpenIDConnect`
   - Need to consolidate or cross-reference appropriately

**Scheme Mapping Understanding:**
- `api_key` → `ADK::Auth::Schemes::ApiKey` ✅
- `http_bearer` → `ADK::Auth::Schemes::HTTPBearer` ✅
- `oauth2` → `ADK::Auth::Schemes::OAuth2` ✅
- `oidc` → `ADK::Auth::Schemes::OpenIDConnect` (alias: OIDC) ✅
- `openid_connect` → `ADK::Auth::Schemes::OpenIDConnect` ✅
- `service_account` → `ADK::Auth::Schemes::ServiceAccount` ✅
- `google_service_account` → `ADK::Auth::Schemes::GoogleServiceAccount` ✅

### Phase 2: Implementation Plan

**Required Changes:**
1. Update `oidc.md` to reference correct class name `OpenIDConnect`
2. Add note about OIDC being an alias for OpenIDConnect
3. Check remaining documentation files for similar issues
4. Verify examples directory for any deprecated references
5. Update any guides that might reference wrong class names
6. Ensure all credential `auth_type` examples use correct values 