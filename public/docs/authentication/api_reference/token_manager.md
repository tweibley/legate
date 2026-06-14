# Token Lifecycle Management

## Overview

The `Legate::Auth::TokenManager` is responsible for managing the lifecycle of authentication tokens, including token storage, expiration handling, and automatic refresh. It serves as a critical component in the Legate authentication system, ensuring that valid tokens are always available for API requests.

## Class Definition

```ruby
module Legate
  module Auth
    class TokenManager
      # Token lifecycle management implementation
    end
  end
end
```

## Key Features

- Caching of authentication tokens via the token store
- Automatic token refresh before expiration
- Token validation and expiration checking
- Support for all token-based authentication schemes
- Event callbacks for token lifecycle events
- Integration with the Legate token store

## Constructor

### `new`

Creates a new token manager instance.

**Parameters:**
- `token_store` (Legate::Auth::TokenStore): The token store for persisting tokens (positional argument)
- `config` (Hash, optional): Configuration options (positional argument, default: {})

**Examples:**

```ruby
# Create a token manager with a token store
token_store = Legate::Auth::TokenStore.new(session_service)
token_manager = Legate::Auth::TokenManager.new(token_store)

# With configuration options
token_manager = Legate::Auth::TokenManager.new(token_store, { refresh_buffer: 300 })
```

**Configuration keys** (with defaults):

| Key | Default | Description |
|-----|---------|-------------|
| `refresh_buffer` | `60` | Seconds before expiration to trigger refresh |
| `retry_max_attempts` | `3` | Maximum number of refresh retry attempts |
| `retry_delay` | `2` | Initial delay between retries (seconds) |
| `retry_backoff` | `1.5` | Backoff multiplier for subsequent retries |
| `auto_refresh` | `true` | Whether to automatically refresh tokens |
| `background_refresh` | `false` | Whether to refresh tokens in the background |

## Instance Methods

### `get_token`

Retrieves a valid token for the given scheme and credential, refreshing if necessary.

**Parameters:**
- `scheme` (Legate::Auth::Scheme): The authentication scheme
- `credential` (Legate::Auth::Credential): The credential to get a token for
- `force_refresh` (Boolean, optional): Force a token refresh even if the current token is valid (default: false)

**Returns:**
- Legate::Auth::ExchangedCredential: A valid token

**Examples:**

```ruby
# Get a token (will auto-refresh if expired)
token = token_manager.get_token(scheme, credential)

# Force a fresh token
token = token_manager.get_token(scheme, credential, force_refresh: true)
```

### `refresh_token`

Refreshes a token using the scheme's refresh mechanism.

**Parameters:**
- `scheme` (Legate::Auth::Scheme): The authentication scheme
- `credential` (Legate::Auth::Credential): The credential associated with the token
- `token` (Legate::Auth::ExchangedCredential, optional): The token to refresh (default: nil)
- `cache_key` (String, optional): The cache key for the token (default: nil)

**Returns:**
- Legate::Auth::ExchangedCredential: The refreshed token

**Examples:**

```ruby
# Refresh a specific token
refreshed = token_manager.refresh_token(scheme, credential, token)

# Refresh with a cache key
refreshed = token_manager.refresh_token(scheme, credential, token, 'my_cache_key')
```

### `invalidate_token`

Invalidates a cached token, removing it from the store.

**Parameters:**
- `cache_key` (String): The cache key of the token to invalidate

**Examples:**

```ruby
token_manager.invalidate_token('oauth2_client123')
```

### `revoke_token`

Revokes a token using the scheme's revocation mechanism.

**Parameters:**
- `scheme` (Legate::Auth::Scheme): The authentication scheme
- `credential` (Legate::Auth::Credential): The credential associated with the token
- `token` (Legate::Auth::ExchangedCredential): The token to revoke

**Examples:**

```ruby
token_manager.revoke_token(scheme, credential, token)
```

### `on`

Registers an event callback for token lifecycle events.

**Parameters:**
- `event` (Symbol): The event to listen for. Valid events are `:before_expiry`, `:refresh_success`, `:refresh_failure`, and `:invalidated`. Any other event raises `ArgumentError`.
- `&callback` (Block): The callback to invoke when the event occurs

Each callback receives a **single Hash** argument with keys including `:event`, `:token`, `:scheme`, `:credential` (plus event-specific extras such as `:error` for `:refresh_failure` or `:cache_key` for `:invalidated`).

**Examples:**

```ruby
# Listen for successful token refreshes
token_manager.on(:refresh_success) do |data|
  puts "Token refreshed for #{data[:scheme]&.scheme_type}"
end

# Listen for tokens approaching expiry
token_manager.on(:before_expiry) do |data|
  puts "Token approaching expiration"
end

# Listen for refresh failures
token_manager.on(:refresh_failure) do |data|
  puts "Refresh failed: #{data[:error]&.message}"
end
```

## Usage

### Basic Usage

```ruby
# Create a token store and manager
token_store = Legate::Auth::TokenStore.new(session_service)
token_manager = Legate::Auth::TokenManager.new(token_store)

# Get a token for an OAuth2 flow
token = token_manager.get_token(oauth2_scheme, oauth2_credential)

# Use the token
puts token[:access_token]
```

### With Automatic Refresh

```ruby
# The token manager automatically refreshes expired tokens
token = token_manager.get_token(scheme, credential)

# If the token is expired and the scheme supports refresh,
# it will be automatically refreshed before being returned
```

## Token Structure

Tokens are stored as Legate::Auth::ExchangedCredential objects with attributes like:

```ruby
{
  access_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
  refresh_token: 'rtok_abc123...',
  id_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...', # Optional, for OIDC
  token_type: 'Bearer',
  expires_in: 3600
}
```

## Integration with Authentication Schemes

The token manager integrates with authentication schemes to handle scheme-specific token operations:

```ruby
# OAuth2 token management
token = token_manager.get_token(oauth2_scheme, oauth2_credential)

# Service account token management
token = token_manager.get_token(service_account_scheme, sa_credential)
```

## Related Classes

- [`Legate::Auth::TokenStore`](./token_store): Secure storage for tokens
- [`Legate::Auth::ExchangedCredential`](./exchanged_credential): Container for exchanged credentials
- [`Legate::Auth::Schemes::OAuth2`](./schemes/oauth2): OAuth2 authentication scheme
- [`Legate::Auth::ExconMiddleware`](./excon_middleware): HTTP client middleware
