# Token Store

## Overview

The `Legate::Auth::TokenStore` class caches authentication tokens in scoped session state (under the `auth` scope). It serves as the foundation for token management within the Legate authentication system.

> **Note:** `TokenStore` does **not** encrypt tokens. `store` persists the plaintext result of `token.to_h` into scoped state, and `get` reads it back as-is. For at-rest encryption, use the opt-in [`Legate::Auth::Encryption`](./encryption) module yourself.

## Class Definition

```ruby
module Legate
  module Auth
    class TokenStore
      # Token store implementation
    end
  end
end
```

## Key Features

- Caching of authentication tokens in scoped session state
- Automatic expiry check on retrieval (expired tokens are cleared and return `nil`)
- Integration with Legate session service
- Token retrieval by key
- Support for multiple token sets

## Constructor

### `new`

Creates a new token store instance.

**Parameters:**
- `session_service` (Legate::SessionService::Base): The session service for persisting token data (positional argument)

**Examples:**

```ruby
# Create a token store with the session service
token_store = Legate::Auth::TokenStore.new(session_service)
```

## Instance Methods

### `store`

Stores a token under the given key by serializing it with `token.to_h` and saving it to scoped state. Only `Legate::Auth::ExchangedCredential` instances are accepted; anything else returns `false`.

**Parameters:**
- `key` (String): The key to store the token under
- `token` (Legate::Auth::ExchangedCredential): The token to store

**Returns:**
- Boolean: `true` if the token was stored, `false` otherwise

**Examples:**

```ruby
token_store.store('oauth2_client123', exchanged_credential)
```

### `get`

Retrieves the token stored under the specified key, deserializing it back into an `ExchangedCredential`. If the stored token is expired it is cleared and `nil` is returned.

**Parameters:**
- `key` (String): The key to retrieve the token for

**Returns:**
- Legate::Auth::ExchangedCredential, or nil if not found or expired

**Examples:**

```ruby
token = token_store.get('oauth2_client123')
```

### `clear`

Removes the token stored under the specified key.

**Parameters:**
- `key` (String): The key of the token to remove

**Examples:**

```ruby
token_store.clear('oauth2_client123')
```

### `clear_all`

Removes all tokens from the token store.

**Examples:**

```ruby
token_store.clear_all
```

## Token Storage and At-Rest Encryption

The token store persists tokens as plaintext `token.to_h` data in scoped session state. It does **not** encrypt them. The security of stored tokens therefore depends on the underlying session service (for example, in-memory storage in the default container deployment).

If you need at-rest encryption, apply the opt-in [`Legate::Auth::Encryption`](./encryption) module in your own storage layer (it requires the `rbnacl` gem and a Base64 key in `LEGATE_AUTH_ENCRYPTION_KEY`).

```ruby
# Tokens are stored as-is (no automatic encryption)
token_store.store('client123', token)

# Retrieved as-is (expired tokens are cleared and return nil)
token = token_store.get('client123')
```

## Integration with Session Service

The token store integrates with the Legate session service to persist tokens across requests:

```ruby
# Create an in-memory session service
session_service = Legate::SessionService::InMemory.new

# Create a token store with the session service
token_store = Legate::Auth::TokenStore.new(session_service)
```

## Usage with Token Manager

The token store is typically used via the `TokenManager` rather than directly:

```ruby
# Create a token store and manager
token_store = Legate::Auth::TokenStore.new(session_service)
token_manager = Legate::Auth::TokenManager.new(token_store)

# The token manager uses the store internally
token = token_manager.get_token(scheme, credential)
```

## Related Classes

- [`Legate::Auth::TokenManager`](./token_manager): Token lifecycle management
- [`Legate::Auth::Encryption`](./encryption): Opt-in encryption utilities (not wired into TokenStore)
- [`Legate::SessionService::Base`](../../core_concepts/legate_session_service): Base session service class
