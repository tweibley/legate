# Token Lifecycle Management

## Overview

The `Adk::Auth::TokenManager` is responsible for managing the lifecycle of authentication tokens, including token storage, expiration handling, and automatic refresh. It serves as a critical component in the ADK authentication system, ensuring that valid tokens are always available for API requests.

## Class Definition

```ruby
module Adk
  module Auth
    class TokenManager
      # Token lifecycle management implementation
    end
  end
end
```

## Key Features

- Secure storage of authentication tokens
- Automatic token refresh before expiration
- Token validation and expiration checking
- Support for all token-based authentication schemes
- Integration with the ADK token store

## Usage

### Basic Usage

```ruby
# Create a token manager
token_manager = Adk::Auth::TokenManager.new(
  token_store: session.token_store,
  scheme: oauth2_scheme
)

# Store tokens
token_manager.store_tokens(
  credential_id: 'client123',
  access_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
  refresh_token: 'rtok_abc123...',
  expires_at: Time.now + 3600
)

# Retrieve tokens
tokens = token_manager.get_tokens(credential_id: 'client123')

# Check if tokens are valid
if token_manager.valid_tokens?(credential_id: 'client123')
  # Use tokens for API requests
end

# Refresh tokens if needed
refreshed_tokens = token_manager.refresh_tokens_if_needed(
  credential_id: 'client123',
  credential: oauth2_credential
)
```

## Token Storage

The token manager uses the `Adk::Auth::TokenStore` to securely store tokens. The token store ensures that sensitive token information is encrypted before being persisted.

```ruby
# Create a token store with the session service
token_store = Adk::Auth::TokenStore.new(session_service: session_service)

# Create a token manager with the token store
token_manager = Adk::Auth::TokenManager.new(
  token_store: token_store,
  scheme: scheme
)
```

## Token Structure

Tokens are stored with the following structure:

```ruby
{
  access_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
  refresh_token: 'rtok_abc123...',
  id_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...', # Optional, for OIDC
  token_type: 'Bearer',
  expires_at: 1716742800, # Unix timestamp
  scope: 'read write'
}
```

## Automatic Token Refresh

The token manager automatically refreshes tokens when they are about to expire:

```ruby
# Get tokens with automatic refresh
tokens = token_manager.get_valid_tokens(
  credential_id: 'client123',
  credential: oauth2_credential,
  refresh: true
)
```

The refresh mechanism works as follows:

1. When `get_valid_tokens` is called with `refresh: true`, the token manager checks if tokens exist and are valid
2. If tokens exist but are expired or close to expiration, it attempts to refresh them
3. If refresh succeeds, the new tokens are stored and returned
4. If refresh fails, an error is raised

## Token Validation

The token manager provides methods to check if tokens are valid:

```ruby
# Check if tokens exist and are valid
if token_manager.valid_tokens?(credential_id: 'client123')
  # Tokens are valid
end

# Check if tokens are expired
if token_manager.tokens_expired?(credential_id: 'client123')
  # Tokens are expired
end

# Check if tokens need refresh (close to expiration)
if token_manager.tokens_need_refresh?(credential_id: 'client123')
  # Tokens should be refreshed
end
```

## Integration with Authentication Schemes

The token manager integrates with authentication schemes to handle scheme-specific token refresh:

```ruby
# OAuth2 token refresh
refreshed_tokens = token_manager.refresh_tokens(
  credential_id: 'client123',
  credential: oauth2_credential,
  scheme: oauth2_scheme
)

# OIDC token refresh
refreshed_tokens = token_manager.refresh_tokens(
  credential_id: 'client123',
  credential: oidc_credential,
  scheme: oidc_scheme
)
```

## Error Handling

The token manager can raise the following errors:

- `Adk::Auth::Error::TokenNotFoundError`: No tokens found for the given credential ID
- `Adk::Auth::Error::TokenRefreshError`: Failed to refresh tokens
- `Adk::Auth::Error::TokenExpiredError`: Tokens are expired and cannot be refreshed
- `Adk::Auth::Error::InvalidTokenError`: Tokens exist but are invalid

## Configuration Options

| Option | Type | Description |
|--------|------|-------------|
| `token_store` | `Adk::Auth::TokenStore` | Store for persisting tokens |
| `scheme` | `Adk::Auth::Scheme` | Authentication scheme to use |
| `refresh_threshold` | `Integer` | Seconds before expiration to trigger refresh (default: 300) |

## Related Classes

- [`Adk::Auth::TokenStore`](./token_store.md): Secure storage for tokens
- [`Adk::Auth::ExchangedCredential`](./exchanged_credential.md): Container for exchanged credentials
- [`Adk::Auth::Schemes::OAuth2`](./schemes/oauth2.md): OAuth2 authentication scheme
- [`Adk::Auth::ExconMiddleware`](./excon_middleware.md): HTTP client middleware 