# Token Store

## Overview

The `Adk::Auth::TokenStore` class provides secure storage for authentication tokens, ensuring that sensitive token information is encrypted before being persisted. It serves as the foundation for token management within the ADK authentication system.

## Class Definition

```ruby
module Adk
  module Auth
    class TokenStore
      # Token store implementation
    end
  end
end
```

## Key Features

- Secure storage of authentication tokens
- Transparent encryption and decryption
- Integration with ADK session service
- Token retrieval by credential ID
- Support for multiple token sets

## Usage

### Basic Usage

```ruby
# Create a token store with the session service
token_store = Adk::Auth::TokenStore.new(
  session_service: session_service
)

# Store tokens
token_store.store(
  credential_id: 'client123',
  tokens: {
    access_token: 'access_token_value',
    refresh_token: 'refresh_token_value',
    expires_at: Time.now + 3600
  }
)

# Retrieve tokens
tokens = token_store.get(credential_id: 'client123')

# Check if tokens exist
if token_store.has_tokens?(credential_id: 'client123')
  # Tokens exist
end

# Delete tokens
token_store.delete(credential_id: 'client123')
```

## Token Encryption

The token store automatically encrypts sensitive token information before storing it in the session service. This ensures that tokens are secure even if the underlying storage is compromised.

```ruby
# Tokens are automatically encrypted when stored
token_store.store(credential_id: 'client123', tokens: tokens)

# Tokens are automatically decrypted when retrieved
decrypted_tokens = token_store.get(credential_id: 'client123')
```

## Integration with Session Service

The token store integrates with the ADK session service to persist tokens across requests:

```ruby
# Create a Redis session service
session_service = Adk::SessionService::Redis.new(
  redis_url: 'redis://localhost:6379/0'
)

# Create a token store with the session service
token_store = Adk::Auth::TokenStore.new(
  session_service: session_service
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

## Methods

### `store`

Stores the provided tokens securely, encrypting sensitive information.

```ruby
token_store.store(
  credential_id: 'client123',
  tokens: {
    access_token: 'access_token_value',
    refresh_token: 'refresh_token_value',
    expires_at: Time.now + 3600
  }
)
```

### `get`

Retrieves and decrypts the tokens for the specified credential ID.

```ruby
tokens = token_store.get(credential_id: 'client123')
```

### `has_tokens?`

Checks if tokens exist for the specified credential ID.

```ruby
if token_store.has_tokens?(credential_id: 'client123')
  # Tokens exist
end
```

### `delete`

Deletes the tokens for the specified credential ID.

```ruby
token_store.delete(credential_id: 'client123')
```

### `clear`

Deletes all tokens stored in the token store.

```ruby
token_store.clear
```

## Session State Storage

The token store uses a specific key in the session state to store tokens:

```ruby
# Tokens are stored in the session state under this key
session_state[:auth_tokens] = {
  'client123' => encrypted_tokens,
  'client456' => encrypted_tokens
  # ...
}
```

## Error Handling

The token store can raise the following errors:

- `Adk::Auth::Error::TokenStoreError`: Base class for all token store errors
- `Adk::Auth::Error::TokenNotFoundError`: No tokens found for the given credential ID
- `Adk::Auth::Error::TokenEncryptionError`: Failed to encrypt or decrypt tokens

## Configuration Options

| Option | Type | Description |
|--------|------|-------------|
| `session_service` | `Adk::SessionService::Base` | Service for persisting session state |
| `state_key` | `Symbol` | Key to use in session state (default: `:auth_tokens`) |

## Related Classes

- [`Adk::Auth::TokenManager`](./token_manager.md): Token lifecycle management
- [`Adk::Auth::Encryption`](./encryption.md): Encryption utilities for secure storage
- [`Adk::SessionService::Base`](../../core_concepts/session_service.md): Base session service class 