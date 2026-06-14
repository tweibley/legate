# Authentication API Reference

This section provides comprehensive documentation for all authentication-related classes and methods in the Legate Ruby library.

## Core Classes

- [Legate::Auth::Scheme](./scheme) - Abstract base class for authentication schemes
- [Legate::Auth::Credential](./credential) - Container for authentication credentials
- [Legate::Auth::Config](./config) - Configuration for authentication flows
- [Legate::Auth::ExchangedCredential](./exchanged_credential) - Container for exchanged credentials

## Authentication Schemes

- [Legate::Auth::Schemes::ApiKey](./schemes/api_key) - API Key authentication scheme
- [Legate::Auth::Schemes::HTTPBearer](./schemes/http_bearer) - HTTP Bearer authentication scheme
- [Legate::Auth::Schemes::OAuth2](./schemes/oauth2) - OAuth2 authentication scheme
- [Legate::Auth::Schemes::OpenIDConnect](./schemes/openid_connect) - OpenID Connect authentication scheme
- [Legate::Auth::Schemes::ServiceAccount](./schemes/service_account) - Service Account authentication scheme
- [Legate::Auth::Schemes::GoogleServiceAccount](./schemes/google_service_account) - Google Service Account authentication scheme

## Authentication Management

- [Legate::Auth::TokenManager](./token_manager) - Token lifecycle management
- [Legate::Auth::TokenStore](./token_store) - Secure token storage
- [Legate::Auth::Encryption](./encryption) - Opt-in encryption utilities (not wired into TokenStore)

## Integration

- [Legate::Auth::ToolContextExtension](./tool_context_extension) - Tool context authentication extensions
- [Legate::Auth::ExconMiddleware](./excon_middleware) - Middleware for Excon HTTP client 