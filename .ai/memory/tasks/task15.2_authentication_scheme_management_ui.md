---
id: 15.2
title: 'Authentication Scheme Management UI'
status: completed
priority: high
feature: Authentication System
dependencies:
  - 15.1
assigned_agent: claude
created_at: "2025-05-25T02:17:22Z"
updated_at: "2025-05-25T02:53:30Z"
started_at: "2025-05-25T02:38:15Z"
completed_at: "2025-05-25T02:53:30Z"
error_log: null
---

## Description

Build UI for viewing and managing authentication schemes available in the authentication manager.

## Details

### Scheme Management Interface
Create comprehensive UI for managing authentication schemes:

- **Scheme List View**: Display all registered authentication schemes (API Key, OAuth2, OIDC, Service Account, etc.)
- **Scheme Details**: Show configuration options and requirements for each scheme type
- **Scheme Registration**: Interface for registering new scheme instances with custom configurations
- **Scheme Configuration**: Forms for modifying existing scheme settings

### Core Functionality
- **View All Schemes**: List all schemes registered in `ADK::Auth::Manager.instance`
- **Scheme Details**: Display scheme type, configuration options, and compatibility information
- **Scheme Documentation**: Built-in help explaining when and how to use each scheme type
- **Configuration Forms**: Dynamic forms based on scheme type requirements

### Routes to Implement
- `GET /auth/schemes` - Enhanced scheme listing with detailed view
- `GET /auth/schemes/:name` - Individual scheme details and configuration
- `POST /auth/schemes` - Register new scheme instance  
- `PUT /auth/schemes/:name` - Update scheme configuration
- `DELETE /auth/schemes/:name` - Remove scheme instance

### UI Components (Bulma CSS + HTMX)
- **Scheme Cards**: Visual cards showing scheme type, status, and key information
- **Configuration Modal**: Modal dialogs for scheme setup and editing
- **Help Sections**: Collapsible help content explaining each scheme type
- **Dynamic Forms**: Forms that adapt based on selected scheme type
- **Status Indicators**: Visual indicators showing scheme health and configuration status

### Integration Features
- **Scheme Validation**: Real-time validation of scheme configurations
- **Compatibility Check**: Show which credential types work with each scheme
- **Usage Information**: Display which agents or URL mappings use each scheme
- **Import/Export**: Backup and restore scheme configurations

### Security Considerations
- **Safe Configuration**: Ensure sensitive scheme configuration (like client secrets) are handled securely
- **Validation**: Proper validation of all scheme configuration inputs
- **Access Control**: Appropriate controls for scheme modification operations

## Test Strategy

- Verify all scheme types are properly displayed
- Test scheme registration with various configuration options
- Validate form inputs and error handling
- Confirm HTMX dynamic updates work correctly for scheme operations
- Test scheme deletion with proper dependency checking 