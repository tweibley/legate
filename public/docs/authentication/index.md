# Authentication in Legate Ruby

## Overview

The Legate Ruby library provides a comprehensive framework for handling various authentication schemes required by external APIs. It supports common authentication methods including API Keys, OAuth2, OpenID Connect (OIDC), and Service Accounts, with a unified interface for both interactive and non-interactive flows.

## Key Features

- **Multiple Authentication Schemes**: Support for API Keys, HTTP Bearer tokens, OAuth2, OpenID Connect, and Service Account authentication
- **Interactive Flows**: Fiber-based control flow for OAuth2 and OIDC authentication requiring user interaction
- **Non-Interactive Flows**: Streamlined handling of API Keys, Bearer tokens, and Service Accounts
- **Scoped Storage**: Tokens cached in scoped session state, with opt-in at-rest encryption via `Legate::Auth::Encryption`
- **Token Lifecycle**: Automatic management of token expiration, refresh, and invalidation
- **Middleware Integration**: Seamless integration with HTTP clients (Excon) for attaching auth to tool requests
- **Middleware Support**: Excon middleware for automatic authentication header injection

## Core Components

- **`Legate::Auth::Scheme`**: Abstract base class defining how APIs expect credentials
- **`Legate::Auth::Credential`**: Container for initial authentication information
- **`Legate::Auth::Config`**: Configuration for the authentication flow
- **`Legate::Auth::ExchangedCredential`**: Container for exchanged tokens and state
- **`Legate::Auth::TokenManager`**: Handles token lifecycle management
- **`Legate::Auth::Encryption`**: Optional, opt-in module for encrypting sensitive credential data at rest

## Authentication Flows

1. **Interactive Flow** (OAuth2/OIDC)
   - Tool requires authentication → Legate detects missing credentials
   - Legate yields control to client application with auth URL
   - User completes authentication in browser
   - Client application resumes Legate execution with auth code
   - Legate exchanges code for tokens and retries the original request

2. **Non-Interactive Flow** (API Key/Bearer Token)
   - Tool is configured with credentials upfront
   - Legate automatically includes credentials in API requests
   - No user interaction required

3. **Service Account Flow**
   - Tool is configured with service account credentials
   - Legate automatically exchanges for access tokens
   - Legate handles token refresh when needed

## Documentation Sections

- [Guides](./guides/index): Detailed guides for implementing authentication
- [API Reference](./api_reference/index): Documentation of all authentication classes and methods
- [Troubleshooting](./troubleshooting/index): Solutions for common authentication issues

## Getting Started

For most cases, you'll want to start with the [Authentication Overview Guide](./guides/overview) to understand the basic concepts, then follow the specific guide for your authentication needs:

- [API Key Authentication](./guides/api_key)
- [OAuth2 Authentication](./guides/oauth2)
- [OpenID Connect](./guides/oidc)
- [Service Account Authentication](./guides/service_account) 