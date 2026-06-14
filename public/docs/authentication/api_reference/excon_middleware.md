# Excon Middleware for Authentication

## Overview

The `Legate::Auth::ExconMiddleware` provides automatic authentication header injection for HTTP requests made using the Excon HTTP client. This middleware simplifies authentication by seamlessly handling token lifecycle, automatic retries for authentication failures, and integrating with the Legate authentication system.

> **Wiring:** You normally don't construct this middleware directly or pass scheme/credential as top-level `Excon.new` keyword arguments. Instead use the helper methods `Legate::Auth.create_connection(url, scheme:, credential:, ...)` or `Legate::Auth.create_middleware(scheme:, credential:, ...)`. When the middleware runs inside Excon's stack it operates as a "shell" instance and reads its configuration from `datum[:connection].data[:auth_middleware_config]`, which the helpers set up for you.

## Class Definition

```ruby
module Legate
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
- Integration with the Legate token lifecycle management
- Support for all authentication schemes (API Key, Bearer, OAuth2, OIDC, Service Account)

## Constructor

### `initialize`

Creates a new ExconMiddleware instance.

**Parameters:**
- `stack` (Object): The Excon middleware stack (positional argument)
- `options` (Hash, optional): Configuration options (positional argument, default: {})

**Options Keys:**
- `:scheme` (Legate::Auth::Scheme): Authentication scheme to use
- `:credential` (Legate::Auth::Credential): Initial authentication credential
- `:token_store` (Legate::Auth::TokenStore): Store for caching tokens
- `:token_manager` (Legate::Auth::TokenManager): Token lifecycle manager
- `:auto_retry` (Boolean): Whether to automatically retry on auth failure
- `:max_retries` (Integer): Maximum number of retry attempts for auth failures (default: 3)
- `:backoff_strategy` (Symbol): Strategy for retry delay (`:none`, `:linear`, `:exponential`)
- `:backoff_factor` (Float): Factor for backoff calculation
- `:retry_non_idempotent` (Boolean): Whether to retry non-idempotent requests
- `:retry_on` (Array): HTTP status codes or exceptions that trigger retries

## Instance Methods

### `request_call`

Called before each request to inject authentication headers.

**Parameters:**
- `datum` (Hash): The Excon request datum

**Returns:**
- Hash: The modified request datum with authentication headers

### `response_call`

Called after each response to check for authentication failures and handle retries.

**Parameters:**
- `datum` (Hash): The Excon response datum

**Returns:**
- Hash: The response datum

### `should_retry?`

Determines if a request should be retried based on the response.

**Parameters:**
- `request_datum` (Hash): The original request datum
- `response_details` (Hash): Details about the response

**Returns:**
- Boolean: `true` if the request should be retried

## Usage

### Basic Usage

```ruby
# Create a connection with authentication middleware via the helper
connection = Legate::Auth.create_connection('https://api.example.com',
  scheme: api_key_scheme,
  credential: api_key_credential
)

# Make authenticated requests
response = connection.get(path: '/protected-resource')
```

### With Token Store

```ruby
# Pass a token store/manager for caching and lifecycle management
connection = Legate::Auth.create_connection('https://api.example.com',
  scheme: oauth2_scheme,
  credential: oauth2_credential,
  token_store: token_store,
  token_manager: token_manager
)
```

### With Retry Configuration

```ruby
connection = Legate::Auth.create_connection('https://api.example.com',
  scheme: scheme,
  credential: credential,
  auto_retry: true,
  max_retries: 3,
  backoff_strategy: :exponential,
  backoff_factor: 2.0,
  retry_on: [401, 403]
)
```

These helpers add `ExconMiddleware` to the connection's middleware stack and store the configured middleware instance on `connection.data[:auth_middleware_config]`, where the shell middleware reads it at request time.

## Example with OAuth2

```ruby
# Create OAuth2 scheme and credential
scheme = Legate::Auth::Schemes::OAuth2.new(
  token_url: 'https://auth.example.com/token',
  authorization_url: 'https://auth.example.com/authorize',
  scopes: ['read', 'write']
)
credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET']
)

# Create connection with OAuth2 authentication
token_store = Legate::Auth::TokenStore.new(session_service)
token_manager = Legate::Auth::TokenManager.new(token_store)

connection = Legate::Auth.create_connection('https://api.example.com',
  scheme: scheme,
  credential: credential,
  token_store: token_store,
  token_manager: token_manager
)

# Make authenticated request
response = connection.get(path: '/user/profile')
```

## Middleware Stack Position

For proper operation, the `ExconMiddleware` should be positioned after any middleware that modifies the request parameters and before middleware that actually makes the HTTP request.

## Integration with Token Lifecycle

The middleware automatically integrates with the Legate token lifecycle management:

1. When a request is made, it checks for existing valid tokens
2. If tokens are expired, it attempts to refresh them automatically
3. If refresh fails or tokens are invalid, it triggers the appropriate authentication flow
4. On successful authentication, it retries the original request

## Related Classes

- [`Legate::Auth::Scheme`](./scheme): Base class for authentication schemes
- [`Legate::Auth::Credential`](./credential): Container for authentication credentials
- [`Legate::Auth::TokenManager`](./token_manager): Manages token lifecycle
- [`Legate::Auth::ToolContextExtension`](./tool_context_extension): Tool context integration
