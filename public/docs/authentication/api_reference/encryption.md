# Encryption Utilities

## Overview

The `Legate::Auth::Encryption` module provides utilities for securely encrypting sensitive authentication data, such as access tokens and refresh tokens. It provides class-level methods for encryption and decryption operations.

Encryption is **opt-in**: it is not wired into `TokenStore` automatically (see [Integration with TokenStore](#integration-with-tokenstore) below). The module uses the [rbnacl](https://github.com/RubyCrypto/rbnacl) gem (libsodium SecretBox) for authenticated encryption. `rbnacl` is an **optional/development dependency** — the encryption methods lazily `require 'rbnacl'` and raise `LoadError` if it (or libsodium) is not installed. Add `gem 'rbnacl'` to your Gemfile and ensure libsodium is available to use this module.

## Module Definition

```ruby
module Legate
  module Auth
    module Encryption
      class << self
        # Encryption class methods
      end
    end
  end
end
```

## Key Features

- Secure encryption of sensitive authentication data
- Authenticated encryption to prevent tampering
- Base64 encoding for safe storage and transmission
- Simple class-level interface for encryption and decryption
- Key generation utility
- Detection of already-encrypted data

## Class Methods

### `encrypt`

Encrypts the provided data.

**Parameters:**
- `data` (String): The data to encrypt (coerced to a string)
- `key` (String, optional): The Base64-encoded encryption key. When omitted (`nil`), the key is read from the `LEGATE_AUTH_ENCRYPTION_KEY` environment variable.

**Returns:**
- String: The encrypted data, prefixed with the `LGTAUTH` header followed by Base64-encoded ciphertext

**Raises:**
- `LoadError`: If the `rbnacl` gem is not available
- `ArgumentError`: If no key is supplied and `LEGATE_AUTH_ENCRYPTION_KEY` is unset, or the key is not valid Base64

**Examples:**

```ruby
# Encrypt using the key from LEGATE_AUTH_ENCRYPTION_KEY
encrypted = Legate::Auth::Encryption.encrypt(sensitive_data)

# Encrypt data with a specific (Base64-encoded) key
encrypted = Legate::Auth::Encryption.encrypt(sensitive_data, my_key)
```

> There is no built-in default key. If neither an explicit key nor `LEGATE_AUTH_ENCRYPTION_KEY` is provided, an `ArgumentError` is raised.

### `decrypt`

Decrypts previously encrypted data.

**Parameters:**
- `encrypted_data` (String): The encrypted data (the `LGTAUTH`-prefixed string returned by `encrypt`)
- `key` (String, optional): The Base64-encoded encryption key. When omitted (`nil`), the key is read from `LEGATE_AUTH_ENCRYPTION_KEY`.

**Returns:**
- String: The decrypted data

**Raises:**
- `LoadError`: If the `rbnacl` gem is not available
- `ArgumentError`: If the data is not in the expected format, the key is missing/invalid, or decryption fails

**Examples:**

```ruby
# Decrypt using the key from LEGATE_AUTH_ENCRYPTION_KEY
decrypted = Legate::Auth::Encryption.decrypt(encrypted_data)

# Decrypt data with a specific (Base64-encoded) key
decrypted = Legate::Auth::Encryption.decrypt(encrypted_data, my_key)
```

### `generate_key`

Generates a new random encryption key, suitable for use as the `key` argument or `LEGATE_AUTH_ENCRYPTION_KEY`.

**Returns:**
- String: A new random key, Base64-encoded

**Raises:**
- `LoadError`: If the `rbnacl` gem is not available

**Examples:**

```ruby
key = Legate::Auth::Encryption.generate_key
# => Base64-encoded string, e.g. "k7Qz...=="
```

### `encrypted?`

Checks if the provided data appears to be encrypted.

**Parameters:**
- `data` (Object): The data to check

**Returns:**
- Boolean: `true` if the data appears to be encrypted

**Examples:**

```ruby
if Legate::Auth::Encryption.encrypted?(data)
  # Data is already encrypted
else
  # Data needs to be encrypted
end
```

## Usage Examples

### Encrypting Authentication Tokens

```ruby
# Encrypt authentication tokens
tokens = {
  access_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
  refresh_token: 'rtok_abc123...',
  expires_at: Time.now.to_i + 3600
}

encrypted_tokens = Legate::Auth::Encryption.encrypt(tokens.to_json)
```

### Decrypting Authentication Tokens

```ruby
# Decrypt authentication tokens
decrypted_json = Legate::Auth::Encryption.decrypt(encrypted_tokens)
decrypted_tokens = JSON.parse(decrypted_json, symbolize_names: true)

access_token = decrypted_tokens[:access_token]
refresh_token = decrypted_tokens[:refresh_token]
```

### Using a Custom Key

```ruby
# Generate a key
key = Legate::Auth::Encryption.generate_key

# Encrypt with the key
encrypted = Legate::Auth::Encryption.encrypt(data, key)

# Decrypt with the same key
decrypted = Legate::Auth::Encryption.decrypt(encrypted, key)
```

## Integration with TokenStore

> **Note:** `Encryption` is **not** wired into `TokenStore`. `TokenStore#store` persists the plaintext result of `token.to_h` into scoped session state, and `TokenStore#get` reads it back as-is. There is no transparent encryption layer.

If you need at-rest encryption, apply the `Encryption` module yourself — for example, encrypt the serialized token before persisting it through your own storage layer, and decrypt on read:

```ruby
# Opt-in: encrypt the serialized token yourself before persisting
require 'json'

key = ENV['LEGATE_AUTH_ENCRYPTION_KEY'] # or Legate::Auth::Encryption.generate_key
ciphertext = Legate::Auth::Encryption.encrypt(token.to_h.to_json, key)
# ...persist `ciphertext` wherever you control storage...

# On read:
plaintext = Legate::Auth::Encryption.decrypt(ciphertext, key)
token = Legate::Auth::ExchangedCredential.from_h(JSON.parse(plaintext, symbolize_names: true))
```

## Key Management

Best practices for key management include:

1. **Environment Variables**: Store the Base64-encoded key in `LEGATE_AUTH_ENCRYPTION_KEY`
2. **Secrets Manager**: Use a secrets manager to securely store and retrieve the key
3. **Key Rotation**: Implement a key rotation strategy for enhanced security
4. **Consistent Key**: Ensure the same key is used for encryption and decryption

## Security Considerations

- **Key Security**: Protect the encryption key and never hard-code it
- **Secure Key Generation**: Use `generate_key` for cryptographically secure keys
- **Token TTL**: Implement a time-to-live (TTL) for tokens to limit exposure
- **Memory Handling**: Clear sensitive data from memory after use when possible

## Error Handling

Decryption failures (bad format, wrong key, tampered data) raise `ArgumentError`. A missing `rbnacl` gem raises `LoadError`. There is no dedicated `EncryptionError` class.

```ruby
begin
  decrypted_data = Legate::Auth::Encryption.decrypt(encrypted_data)
rescue LoadError => e
  # rbnacl / libsodium not installed
  log.error("Encryption unavailable: #{e.message}")
  nil
rescue ArgumentError => e
  # Decryption failed: invalid format, key, or tampered data
  log.error("Decryption failed: #{e.message}")
  nil
end
```

## Related Classes

- [`Legate::Auth::TokenStore`](./token_store): Secure storage for authentication tokens
- [`Legate::Auth::TokenManager`](./token_manager): Token lifecycle management
