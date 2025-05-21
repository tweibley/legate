# Encryption Utilities

## Overview

The `Adk::Auth::Encryption` class provides utilities for securely encrypting sensitive authentication data, such as access tokens and refresh tokens. It uses the `rbnacl` gem to implement authenticated encryption.

## Class Definition

```ruby
module Adk
  module Auth
    class Encryption
      # Encryption implementation
    end
  end
end
```

## Key Features

- Secure encryption of sensitive authentication data
- Authenticated encryption to prevent tampering
- Base64 encoding for safe storage and transmission
- Simple interface for encryption and decryption

## Usage

### Basic Usage

```ruby
# Create an encryption utility with a secret key
encryption = Adk::Auth::Encryption.new(secret_key)

# Encrypt data
encrypted_data = encryption.encrypt(sensitive_data)

# Decrypt data
decrypted_data = encryption.decrypt(encrypted_data)
```

### Encrypting Authentication Tokens

```ruby
# Encrypt authentication tokens
tokens = {
  access_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
  refresh_token: 'rtok_abc123...',
  expires_at: Time.now.to_i + 3600
}

encrypted_tokens = encryption.encrypt(tokens)
```

### Decrypting Authentication Tokens

```ruby
# Decrypt authentication tokens
decrypted_tokens = encryption.decrypt(encrypted_tokens)

access_token = decrypted_tokens[:access_token]
refresh_token = decrypted_tokens[:refresh_token]
expires_at = decrypted_tokens[:expires_at]
```

## Encryption Implementation

The `Encryption` class uses the `RbNaCl::SimpleBox` for authenticated encryption, which provides both confidentiality and integrity protection:

```ruby
def initialize(key)
  # Ensure the key is the correct length (32 bytes)
  if key.bytesize != 32
    # If not, derive a 32-byte key using BLAKE2b
    key = RbNaCl::Hash.blake2b(key, key_size: 32)
  end
  
  # Create a SimpleBox with the key
  @box = RbNaCl::SimpleBox.from_secret_key(key)
end

def encrypt(data)
  # Convert data to JSON if it's not already a string
  json_data = data.is_a?(String) ? data : data.to_json
  
  # Encrypt the data
  encrypted_data = @box.encrypt(json_data)
  
  # Base64 encode for safe storage
  Base64.strict_encode64(encrypted_data)
end

def decrypt(encrypted_data)
  # Base64 decode
  decoded_data = Base64.strict_decode64(encrypted_data)
  
  # Decrypt the data
  decrypted_data = @box.decrypt(decoded_data)
  
  # Parse JSON if needed
  if decrypted_data.start_with?('{') || decrypted_data.start_with?('[')
    JSON.parse(decrypted_data, symbolize_names: true)
  else
    decrypted_data
  end
end
```

## Integration with TokenStore

The `Encryption` class is used by the `TokenStore` to encrypt tokens before storing them in the session:

```ruby
class TokenStore
  def initialize(session_service:)
    @session_service = session_service
    @state = session_service.get_state || {}
    
    # Create encryption with a secure key
    @encryption = Adk::Auth::Encryption.new(generate_encryption_key)
  end
  
  def store(credential_id:, tokens:)
    # Encrypt tokens before storage
    encrypted_tokens = @encryption.encrypt(tokens)
    
    # Store in session state
    @state[:auth_tokens] ||= {}
    @state[:auth_tokens][credential_id] = encrypted_tokens
    @session_service.set_state(@state)
    
    tokens
  end
  
  def get(credential_id:)
    # Get encrypted tokens from session state
    return nil unless @state[:auth_tokens]
    return nil unless @state[:auth_tokens][credential_id]
    
    # Decrypt tokens
    @encryption.decrypt(@state[:auth_tokens][credential_id])
  end
  
  private
  
  def generate_encryption_key
    # Generate or retrieve encryption key
    # ...
  end
end
```

## Key Management

The `Encryption` class requires a secure encryption key. Best practices for key management include:

1. **Environment Variables**: Store the encryption key in an environment variable
2. **Secrets Manager**: Use a secrets manager to securely store and retrieve the key
3. **Key Rotation**: Implement a key rotation strategy for enhanced security
4. **Consistent Key**: Ensure the same key is used for encryption and decryption within a session

Example key management implementation:

```ruby
def generate_encryption_key
  # Option 1: Use an environment variable
  env_key = ENV['ADK_ENCRYPTION_KEY']
  return env_key if env_key && !env_key.empty?
  
  # Option 2: Generate a key based on a secret and session ID
  secret = ENV['ADK_SECRET'] || 'default-secret'
  session_id = @session_service.session_id
  combined_key = "#{secret}:#{session_id}"
  
  # Derive a 32-byte key using BLAKE2b
  RbNaCl::Hash.blake2b(combined_key, key_size: 32)
end
```

## Security Considerations

- **Key Security**: Protect the encryption key and never hard-code it
- **Key Length**: Use a 32-byte (256-bit) key for maximum security
- **Secure Key Generation**: Use a cryptographically secure random number generator
- **Token TTL**: Implement a time-to-live (TTL) for tokens to limit exposure
- **Memory Handling**: Clear sensitive data from memory after use when possible

## Error Handling

The `Encryption` class can raise the following errors:

- `Adk::Auth::Error::EncryptionError`: Base class for all encryption errors
- `Adk::Auth::Error::InvalidKeyError`: The provided key is not valid
- `Adk::Auth::Error::DecryptionError`: Failed to decrypt the data

Example error handling:

```ruby
begin
  decrypted_data = encryption.decrypt(encrypted_data)
rescue Adk::Auth::Error::DecryptionError => e
  # Handle decryption failure
  log.error("Decryption failed: #{e.message}")
  nil
end
```

## Related Classes

- [`Adk::Auth::TokenStore`](./token_store.md): Secure storage for authentication tokens
- [`Adk::Auth::TokenManager`](./token_manager.md): Token lifecycle management
- [`Adk::SessionService::Redis`](../../core_concepts/session_service.md): Redis session service 