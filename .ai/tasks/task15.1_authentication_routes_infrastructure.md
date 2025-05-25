---
id: 15.1
title: 'Authentication Routes Infrastructure'
status: pending
priority: high
feature: Authentication System
dependencies:
  - 5
  - 6
  - 7
  - 9
  - 10
assigned_agent: null
created_at: "2025-05-25T02:17:22Z"
updated_at: "2025-05-25T02:17:22Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Create the core authentication routes module and basic integration with the existing web UI architecture.

## Details

### Authentication Routes Module (`lib/adk/web/routes/authentication_routes.rb`)
Create a new route module following the existing pattern in the ADK web UI:

- **Module Structure**: Follow the pattern used by other route modules like `AgentRuntimeRoutes`
- **Registration**: Register the module in `lib/adk/web/app.rb` alongside other route modules
- **Basic Routes**: Implement foundational routes for authentication management
- **Integration Points**: Ensure proper access to the authentication manager and other services

### Core Routes to Implement
- `GET /auth` - Main authentication management dashboard 
- `GET /auth/schemes` - List all available authentication schemes
- `GET /auth/credentials` - List all configured credentials
- `GET /auth/mappings` - List all URL mappings
- `GET /auth/debug` - Debug information about authentication state

### Integration with Existing Architecture
- **Authentication Manager Access**: Use `ADK::Auth::Manager.instance` for all authentication operations
- **Session Integration**: Use existing session management (`session[:web_user_id]`)
- **Error Handling**: Follow existing error handling patterns from other route modules
- **HTMX Support**: Prepare structure for HTMX-based dynamic updates
- **Security**: Follow existing security patterns for sensitive data handling

### Slim Templates Structure
Create basic template structure in `lib/adk/web/views/`:
- `auth.slim` - Main authentication dashboard layout
- `auth/` directory for authentication-specific partials
- Follow existing template patterns and Bulma CSS styling

### Navigation Integration
- Add authentication management link to main navigation
- Ensure proper active state highlighting
- Follow existing navigation patterns

## Test Strategy

- Verify the authentication routes module is properly registered
- Test that basic routes respond correctly (200 status codes)
- Confirm authentication manager is accessible from routes
- Validate navigation integration works correctly
- Test error handling for authentication manager unavailability 