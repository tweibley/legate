# Authentication API Reference

This section provides comprehensive documentation for all authentication-related classes and methods in the ADK Ruby library.

## Core Classes

- [Adk::Auth::Scheme](./scheme.md) - Abstract base class for authentication schemes
- [Adk::Auth::Credential](./credential.md) - Container for authentication credentials
- [Adk::Auth::Config](./config.md) - Configuration for authentication flows
- [Adk::Auth::ExchangedCredential](./exchanged_credential.md) - Container for exchanged credentials

## Authentication Schemes

- [Adk::Auth::Schemes::APIKey](./schemes/api_key.md) - API Key authentication scheme
- [Adk::Auth::Schemes::HTTPBearer](./schemes/http_bearer.md) - HTTP Bearer authentication scheme
- [Adk::Auth::Schemes::OAuth2](./schemes/oauth2.md) - OAuth2 authentication scheme
- [Adk::Auth::Schemes::OpenIDConnect](./schemes/openid_connect.md) - OpenID Connect authentication scheme
- [Adk::Auth::Schemes::ServiceAccount](./schemes/service_account.md) - Service Account authentication scheme
- [Adk::Auth::Schemes::GoogleServiceAccount](./schemes/google_service_account.md) - Google Service Account authentication scheme

## Authentication Management

- [Adk::Auth::TokenManager](./token_manager.md) - Token lifecycle management
- [Adk::Auth::TokenStore](./token_store.md) - Secure token storage
- [Adk::Auth::Encryption](./encryption.md) - Encryption utilities for secure storage

## Integration

- [Adk::Auth::ToolContextExtension](./tool_context_extension.md) - Tool context authentication extensions
- [Adk::Auth::ExconMiddleware](./excon_middleware.md) - Middleware for Excon HTTP client
- [Adk::Auth::Runner](./runner.md) - Authentication integration with the ADK Runner

## Coordinators

- [Adk::Auth::Coordinator](./coordinator.md) - Base authentication coordinator
- [Adk::Auth::Coordinators::OAuth2](./coordinators/oauth2.md) - OAuth2 flow coordinator
- [Adk::Auth::Coordinators::OIDC](./coordinators/oidc.md) - OpenID Connect flow coordinator
- [Adk::Auth::Coordinators::ServiceAccount](./coordinators/service_account.md) - Service Account flow coordinator

## Error Handling

- [Adk::Auth::Error](./error.md) - Base authentication error class 