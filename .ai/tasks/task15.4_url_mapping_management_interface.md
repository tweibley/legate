---
id: 15.4
title: 'URL Mapping Management Interface'
status: pending
priority: medium
feature: Authentication System
dependencies:
  - 15.2
  - 15.3
assigned_agent: null
created_at: "2025-05-25T02:17:22Z"
updated_at: "2025-05-25T02:17:22Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Build interface for configuring URL to authentication scheme/credential mappings.

## Details

### URL Mapping Management Interface
Create UI for managing URL pattern to authentication mappings:

- **Mapping List View**: Display all configured URL mappings with their associated schemes and credentials
- **Mapping Creation**: Forms for creating new URL pattern mappings
- **Mapping Editing**: Interface for updating existing mappings
- **Pattern Testing**: Tools to test URL pattern matching

### Core Functionality
- **View All Mappings**: List all URL mappings registered in the authentication manager
- **Add Mappings**: Forms for creating URL pattern to scheme/credential associations
- **Edit Mappings**: Update existing URL mappings with new patterns or authentication
- **Delete Mappings**: Remove URL mappings with conflict checking
- **Test Patterns**: Validate that URL patterns match expected URLs

### Routes to Implement
- `GET /auth/mappings` - List all URL mappings
- `GET /auth/mappings/new` - Form for creating new URL mappings
- `GET /auth/mappings/:id` - Individual mapping details and editing
- `POST /auth/mappings` - Create new URL mapping
- `PUT /auth/mappings/:id` - Update existing mapping
- `DELETE /auth/mappings/:id` - Remove mapping
- `POST /auth/mappings/test` - Test URL pattern matching

### UI Components (Bulma CSS + HTMX)
- **Mapping Cards**: Cards showing URL pattern, scheme, credential, and status
- **Pattern Input**: Input fields with pattern validation and examples
- **Scheme/Credential Selectors**: Dropdowns populated from available schemes and credentials
- **Pattern Tester**: Interface to test URL patterns against sample URLs
- **Conflict Detector**: Warnings when patterns might conflict

### URL Pattern Support
- **String Patterns**: Simple string matching for exact URL parts
- **Regex Patterns**: Full regex support for complex pattern matching
- **Wildcard Patterns**: Support for common wildcard patterns
- **Domain Matching**: Special handling for domain-based patterns
- **Path Matching**: Support for path-based pattern matching

### Mapping Configuration
- **URL Pattern**: The pattern to match URLs against (string or regex)
- **Scheme Selection**: Choose from available authentication schemes
- **Credential Selection**: Choose from available credentials compatible with the selected scheme
- **Priority**: Order of evaluation for overlapping patterns
- **Active Status**: Enable/disable mappings without deletion

### Validation and Testing
- **Pattern Validation**: Ensure URL patterns are valid and compilable
- **Compatibility Check**: Verify selected scheme and credential are compatible
- **Conflict Detection**: Warn about overlapping or conflicting patterns
- **URL Testing**: Test specific URLs against the mapping patterns
- **Coverage Analysis**: Show which URLs would match which mappings

## Test Strategy

- Verify URL mapping creation with various pattern types
- Test pattern matching functionality with sample URLs
- Validate scheme/credential compatibility checking
- Confirm conflict detection works for overlapping patterns
- Test mapping deletion and deactivation functionality 