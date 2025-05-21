# Excon Middleware for Authentication

## Overview

The `Adk::Auth::ExconMiddleware` provides automatic authentication header injection for HTTP requests made using the Excon HTTP client. This middleware simplifies authentication by seamlessly handling token lifecycle, automatic retries for authentication failures, and integrating with the ADK authentication system.

## Class Definition

```ruby
module Adk
  module Auth
    class ExconMiddleware < Excon::Middleware::Base
      # Implementation of Excon middleware for authentication
    end
  end
end
```

## Key Features

- Automatic injection of authentication headers based on scheme type
- Token refresh handling for expired credentials
- Configurable retry behavior for authentication failures
- Integration with the ADK token lifecycle management
- Support for all authentication schemes (API Key, Bearer, OAuth2, OIDC, Service Account)

## Usage

### Basic Usage

```ruby
# Create a connection with authentication middleware
connection = Excon.new('https://api.example.com', 
  middlewares: [Adk::Auth::ExconMiddleware.new(scheme: scheme, credential: credential)])

# Make authenticated requests
response = connection.get(path: '/protected-resource')
```

### Using Middleware Factory

```ruby
# Create middleware using the factory
middleware = Adk::Auth.create_middleware(
  scheme: oauth2_scheme,
  credential: oauth2_credential,
  token_store: session.token_store
)

# Create connection with the middleware
connection = Excon.new('https://api.example.com', middlewares: [middleware])
```

### Connection Helpers

```ruby
# Create an authenticated connection directly
connection = Adk::Auth.create_connection(
  'https://api.example.com',
  scheme: api_key_scheme,
  credential: api_key_credential
)
```

## Configuration Options

| Option | Type | Description |
|--------|------|-------------|
| `scheme` | `Adk::Auth::Scheme` | Authentication scheme to use |
| `credential` | `Adk::Auth::Credential` | Initial authentication credential |
| `token_store` | `Adk::Auth::TokenStore` | Store for caching tokens (optional) |
| `max_retries` | `Integer` | Maximum number of retry attempts for auth failures (default: 1) |
| `retry_statuses` | `Array<Integer>` | HTTP status codes that trigger retries (default: [401, 403]) |
| `backoff_strategy` | `:none`, `:linear`, `:exponential` | Strategy for retry delay (default: `:linear`) |
| `backoff_factor` | `Float` | Factor for backoff calculation (default: 1.0) |

## Retry Behavior

The middleware can automatically retry requests that fail with authentication-related status codes (by default 401 and 403). The retry behavior can be configured using the following options:

```ruby
middleware = Adk::Auth.create_middleware(
  scheme: scheme,
  credential: credential,
  max_retries: 3,
  retry_statuses: [401, 403, 407],
  backoff_strategy: :exponential,
  backoff_factor: 2.0
)
```

## Middleware Stack Position

For proper operation, the `ExconMiddleware` should be positioned after any middleware that modifies the request parameters and before middleware that actually makes the HTTP request. When using the `Adk::Auth.create_connection` helper, this is handled automatically.

## Integration with Token Lifecycle

The middleware automatically integrates with the ADK token lifecycle management:

1. When a request is made, it checks for existing valid tokens
2. If tokens are expired, it attempts to refresh them automatically
3. If refresh fails or tokens are invalid, it triggers the appropriate authentication flow
4. On successful authentication, it retries the original request

## Example with OAuth2

```ruby
# Create OAuth2 scheme and credential
scheme = Adk::Auth::Schemes::OAuth2.new(
  token_url: 'https://auth.example.com/token',
  auth_url: 'https://auth.example.com/authorize',
  scopes: ['read', 'write']
)
credential = Adk::Auth::Credential.new(
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET']
)

# Create connection with OAuth2 authentication
connection = Adk::Auth.create_connection(
  'https://api.example.com',
  scheme: scheme,
  credential: credential,
  token_store: session.token_store
)

# Make authenticated request
response = connection.get(path: '/user/profile')
```

## Error Handling

The middleware can raise the following errors:

- `Adk::Auth::Error::AuthenticationError`: Base class for all authentication errors
- `Adk::Auth::Error::TokenRefreshError`: Failed to refresh an expired token
- `Adk::Auth::Error::CredentialError`: Issues with the provided credentials
- `Adk::Auth::Error::MaxRetriesExceeded`: Authentication failed after maximum retries

## Related Classes

- [`Adk::Auth::Scheme`](./scheme.md): Base class for authentication schemes
- [`Adk::Auth::Credential`](./credential.md): Container for authentication credentials
- [`Adk::Auth::TokenManager`](./token_manager.md): Manages token lifecycle
- [`Adk::Auth::ToolContextExtension`](./tool_context_extension.md): Tool context integration 