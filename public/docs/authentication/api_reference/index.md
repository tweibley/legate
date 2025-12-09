# Authentication API Reference

This section provides comprehensive documentation for all authentication-related classes and methods in the ADK Ruby library.

## Core Classes

- [Adk::Auth::Scheme](./scheme) - Abstract base class for authentication schemes
- [Adk::Auth::Credential](./credential) - Container for authentication credentials
- [Adk::Auth::Config](./config) - Configuration for authentication flows
- [Adk::Auth::ExchangedCredential](./exchanged_credential) - Container for exchanged credentials

## Authentication Schemes

- [Adk::Auth::Schemes::APIKey](./schemes/api_key) - API Key authentication scheme
- [Adk::Auth::Schemes::HTTPBearer](./schemes/http_bearer) - HTTP Bearer authentication scheme
- [Adk::Auth::Schemes::OAuth2](./schemes/oauth2) - OAuth2 authentication scheme
- [Adk::Auth::Schemes::OpenIDConnect](./schemes/openid_connect) - OpenID Connect authentication scheme
- [Adk::Auth::Schemes::ServiceAccount](./schemes/service_account) - Service Account authentication scheme
- [Adk::Auth::Schemes::GoogleServiceAccount](./schemes/google_service_account) - Google Service Account authentication scheme

## Authentication Management

- [Adk::Auth::TokenManager](./token_manager) - Token lifecycle management
- [Adk::Auth::TokenStore](./token_store) - Secure token storage
- [Adk::Auth::Encryption](./encryption) - Encryption utilities for secure storage

## Integration

- [Adk::Auth::ToolContextExtension](./tool_context_extension) - Tool context authentication extensions
- [Adk::Auth::ExconMiddleware](./excon_middleware) - Middleware for Excon HTTP client
- [Adk::Auth::Runner](./runner) - Authentication integration with the ADK Runner

## Coordinators

- [Adk::Auth::Coordinator](./coordinator) - Base authentication coordinator
- [Adk::Auth::Coordinators::OAuth2](./coordinators/oauth2) - OAuth2 flow coordinator
- [Adk::Auth::Coordinators::OIDC](./coordinators/oidc) - OpenID Connect flow coordinator
- [Adk::Auth::Coordinators::ServiceAccount](./coordinators/service_account) - Service Account flow coordinator

## Error Handling

- [Adk::Auth::Error](./error) - Base authentication error class 