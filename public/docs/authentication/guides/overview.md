# Authentication Overview

## Introduction

The Legate Ruby authentication system provides a comprehensive framework for handling authentication with external APIs. It supports various authentication methods including:

- API Key authentication
- HTTP Bearer token authentication
- OAuth2 authentication
- OpenID Connect (OIDC) authentication
- Service Account authentication

The system is designed to handle both interactive authentication flows (like OAuth2, which requires user consent) and non-interactive flows (like API Keys), with a unified interface.

## Core Concepts

### Authentication Schemes

An authentication scheme (`Legate::Auth::Scheme`) defines how an API expects credentials to be provided. Each scheme implements:

- How to apply authentication to requests
- How to exchange initial credentials for tokens (if applicable)
- How to refresh tokens (if applicable)
- How to build authorization URIs for interactive flows

The Legate Ruby library includes the following authentication schemes:

- `Legate::Auth::Schemes::ApiKey`: For API key authentication (in header, query, or cookie)
- `Legate::Auth::Schemes::HTTPBearer`: For Bearer token authentication
- `Legate::Auth::Schemes::OAuth2`: For OAuth2 authentication flows
- `Legate::Auth::Schemes::OpenIDConnect`: For OpenID Connect authentication
- `Legate::Auth::Schemes::ServiceAccount`: For service account authentication
- `Legate::Auth::Schemes::GoogleServiceAccount`: For Google Cloud service accounts

### Credentials

A credential (`Legate::Auth::Credential`) contains the initial information needed to start authentication:

- API Keys
- OAuth2 client ID and client secret
- Bearer tokens
- Service account keys

Credentials can be provided directly or through environment variables, which is recommended for sensitive information.

### Token Exchange

For authentication methods like OAuth2, the initial credential must be exchanged for a token:

1. The initial credential (e.g., client ID and secret) is used to start the authentication flow
2. The flow results in an exchanged credential (`Legate::Auth::ExchangedCredential`)
3. The exchanged credential contains access tokens, refresh tokens, and expiry information

### Authentication Flows

#### Non-Interactive Flow (API Key, Bearer Token)

```ruby
# Create an API Key scheme (no constructor arguments)
scheme = Legate::Auth::Schemes::ApiKey.new

# Create a credential with the API key. The key's location ('header',
# 'query', or 'cookie') and name live on the credential, not the scheme.
credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY'],
  location: 'header',   # default
  name: 'X-API-Key'     # default
)

# Attach the scheme/credential to your outbound HTTP client. The simplest
# path is the Excon connection helper, which applies the API key for you:
connection = Legate::Auth.create_connection('https://api.example.com',
  scheme: scheme,
  credential: credential
)
response = connection.get(path: '/protected-resource')
```

#### Interactive Flow (OAuth2, OIDC)

```ruby
# Create an OAuth2 scheme
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['profile', 'email']
)

# Create a credential with client ID and secret
credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET']
)

# Drive the interactive flow via Config:
# 1. Build the authorization URI and redirect the user to it
config = Legate::Auth::Config.new(scheme: scheme, credential: credential)
state = SecureRandom.hex(16)
auth_uri = config.build_authorization_uri('https://your-app.com/callback', state)
# redirect_to auth_uri

# 2. When the user is redirected back, set the response URI on the config
config.response_uri = 'https://your-app.com/callback?code=12345&state=abcde'

# 3. Exchange the authorization code for tokens
token = scheme.exchange_token(config, credential)

# `token` is an ExchangedCredential you can store and apply to requests.
```

> The fiber-based, tool-driven flow (where a tool's `with_authentication`
> block yields an auth request to the caller) is also supported; see
> [`Legate::Auth::ToolContextExtension`](../api_reference/tool_context_extension).

#### Service Account Flow

```ruby
# Create a Service Account scheme
scheme = Legate::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# Create a credential with the service account key (raw JSON string)
credential = Legate::Auth::Credential.new(
  auth_type: :google_service_account,
  service_account_key: File.read('service-account.json')
)

# Exchange for an access token and apply it to outbound requests
token = scheme.exchange_token(credential)
connection = Legate::Auth.create_connection('https://api.example.com',
  scheme: scheme,
  credential: token
)
result = connection.get(path: '/resource')
```

## Security Considerations

The Legate Ruby library implements several security measures:

- Tokens are cached in scoped session state; for at-rest encryption, the opt-in `Legate::Auth::Encryption` module is available (it is not applied automatically)
- Access tokens have limited lifetimes, with automatic expiry checks
- Refresh tokens are handled by the `TokenManager`
- Environment variable resolution (the `ENV:` prefix) keeps sensitive values out of source code
- Outbound auth/token URLs are validated by `Legate::Auth::UrlGuard` to block SSRF to private/loopback addresses

## Next Steps

- [Authentication Configuration](./configuration) - How to configure authentication for different scenarios
- [API Key Authentication](./api_key) - Detailed guide for API key authentication
- [OAuth2 Authentication](./oauth2) - Complete guide for implementing OAuth2 flows
- [Token Lifecycle Management](./token_lifecycle) - Managing token expiration and refresh 