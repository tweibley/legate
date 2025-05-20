# Authentication in ADK Ruby

## Overview

The ADK Ruby library provides a comprehensive framework for handling various authentication schemes required by external APIs. It supports common authentication methods including API Keys, OAuth2, OpenID Connect (OIDC), and Service Accounts, with a unified interface for both interactive and non-interactive flows.

## Key Features

- **Multiple Authentication Schemes**: Support for API Keys, HTTP Bearer tokens, OAuth2, OpenID Connect, and Service Account authentication
- **Interactive Flows**: Fiber-based control flow for OAuth2 and OIDC authentication requiring user interaction
- **Non-Interactive Flows**: Streamlined handling of API Keys, Bearer tokens, and Service Accounts
- **Secure Storage**: Encrypted storage of sensitive credentials in session state
- **Token Lifecycle**: Automatic management of token expiration, refresh, and invalidation
- **Toolset Integration**: Seamless integration with OpenAPI toolsets and custom function tools
- **Middleware Support**: Excon middleware for automatic authentication header injection

## Core Components

- **`Adk::Auth::Scheme`**: Abstract base class defining how APIs expect credentials
- **`Adk::Auth::Credential`**: Container for initial authentication information
- **`Adk::Auth::Config`**: Configuration for the authentication flow
- **`Adk::Auth::ExchangedCredential`**: Container for exchanged tokens and state
- **`Adk::Auth::TokenManager`**: Handles token lifecycle management
- **`Adk::Auth::Encryption`**: Secures sensitive credential data

## Authentication Flows

1. **Interactive Flow** (OAuth2/OIDC)
   - Tool requires authentication → ADK detects missing credentials
   - ADK yields control to client application with auth URL
   - User completes authentication in browser
   - Client application resumes ADK execution with auth code
   - ADK exchanges code for tokens and retries the original request

2. **Non-Interactive Flow** (API Key/Bearer Token)
   - Tool is configured with credentials upfront
   - ADK automatically includes credentials in API requests
   - No user interaction required

3. **Service Account Flow**
   - Tool is configured with service account credentials
   - ADK automatically exchanges for access tokens
   - ADK handles token refresh when needed

## Documentation Sections

- [Guides](./guides/index.md): Detailed guides for implementing authentication
- [API Reference](./api_reference/index.md): Documentation of all authentication classes and methods
- [Troubleshooting](./troubleshooting/index.md): Solutions for common authentication issues

## Getting Started

For most cases, you'll want to start with the [Authentication Overview Guide](./guides/overview.md) to understand the basic concepts, then follow the specific guide for your authentication needs:

- [API Key Authentication](./guides/api_key.md)
- [OAuth2 Authentication](./guides/oauth2.md)
- [OpenID Connect](./guides/oidc.md)
- [Service Account Authentication](./guides/service_account.md) 