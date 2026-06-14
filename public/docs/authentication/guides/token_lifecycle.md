# Token Lifecycle Management

Authentication tokens have a lifecycle that includes acquisition, refresh, and eventual expiration or revocation. The Legate Ruby library provides a comprehensive token management system to handle these aspects automatically.

## Overview

The token lifecycle includes several key phases:

1. **Token Acquisition**: The initial exchange of credentials for a token
2. **Token Storage**: Secure storage of the token for subsequent requests
3. **Token Usage**: Using the token to authenticate API requests
4. **Token Refresh**: Renewing the token before it expires
5. **Token Expiration**: Handling token expiration gracefully
6. **Token Revocation**: Explicitly revoking tokens when no longer needed

## Token Manager

The `Legate::Auth::TokenManager` class handles all aspects of token lifecycle management:

```ruby
# Create a token manager with a token store
token_store = Legate::Auth::TokenStore.new(session)
token_manager = Legate::Auth::TokenManager.new(token_store)

# Get a token (automatically handles acquisition and refresh)
token = token_manager.get_token(scheme, credential)

# Force refresh a token
refreshed_token = token_manager.get_token(scheme, credential, force_refresh: true)

# Invalidate a token in the store
token_manager.invalidate_token(cache_key)

# Revoke a token with the provider
token_manager.revoke_token(scheme, credential, token)
```

## Token Acquisition

Tokens are acquired through different mechanisms depending on the authentication scheme:

### OAuth2/OIDC

```ruby
# OAuth2 token acquisition via authorization code
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['profile', 'email']
)

credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET']
)

# The token is acquired through the Fiber yield/resume mechanism
```

### Service Account

```ruby
# Service account token acquisition
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://oauth2.googleapis.com/token',
  audience: 'https://oauth2.googleapis.com/token',
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: File.read('service-account-key.json')  # raw JSON string
)

# The token is acquired automatically when needed
token = token_manager.get_token(scheme, credential)
```

### API Key

```ruby
# API key "token" creation
scheme = Legate::Auth::Schemes::ApiKey.new

credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY']
)

# Creates a wrapper token that never expires
token = token_manager.get_token(scheme, credential)
```

## Token Storage

Tokens are cached in scoped session state:

```ruby
# The TokenStore caches tokens under the 'auth' scope
token_store = Legate::Auth::TokenStore.new(session_service)

# Store a token
token_store.store(cache_key, token)

# Retrieve a token (returns nil if missing or expired)
token = token_store.get(cache_key)

# Clear a token
token_store.clear(cache_key)
```

### Security Considerations

- Tokens are stored as plaintext (`token.to_h`) in scoped state; `TokenStore` does **not** encrypt them
- For at-rest encryption, apply the opt-in `Legate::Auth::Encryption` module yourself (requires the `rbnacl` gem and a Base64 key in `LEGATE_AUTH_ENCRYPTION_KEY`)
- Sensitive token information should never be logged

## Token Refresh

Most tokens have an expiration time and need to be refreshed:

```ruby
# Configure token refresh settings
token_manager = Legate::Auth::TokenManager.new(token_store, {
  refresh_buffer: 60,       # Refresh 60 seconds before expiration
  retry_max_attempts: 3,    # Try up to 3 times
  retry_delay: 2,           # Wait 2 seconds between attempts
  retry_backoff: 1.5,       # Increase wait time by 1.5x each try
  auto_refresh: true        # Enable automatic refresh
})

# Token refresh is automatic when get_token is called
token = token_manager.get_token(scheme, credential)
```

### Refresh Behavior by Scheme Type

- **OAuth2/OIDC**: Uses the refresh token to obtain a new access token
- **Service Account**: Creates a new JWT assertion and exchanges it for a new token
- **API Key**: No refresh needed (API keys don't expire)
- **Bearer Token**: Can't be refreshed (must re-authenticate)

## Token Expiration

The Legate Ruby library handles token expiration gracefully:

```ruby
# Check if a token is expired
if token.expired?
  # Handle expiration
end

# Check if a token is expired with a buffer time (positional argument)
if token.expired?(60)
  # Token expires within the next 60 seconds
end

# ExchangedCredential includes expiration information
token = Legate::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'access-token',
  refresh_token: 'refresh-token',
  expires_in: 3600          # Token expires in 3600 seconds
)

# Get expiration time
expiry = token.expires_at   # Time object representing expiration
```

## Token Revocation

When a token is no longer needed, it can be explicitly revoked:

```ruby
# Revoke a token with the provider
token_manager.revoke_token(scheme, credential, token)

# Just invalidate it in the store without provider revocation
token_manager.invalidate_token(cache_key)
```

### Revocation Support by Scheme Type

- **OAuth2/OIDC**: Supported if the provider has a revocation endpoint
- **Service Account**: Generally not supported by providers
- **API Key**: Not applicable (API keys must be deleted from the provider's management interface)

## Event Callbacks

The token manager supports callbacks for token lifecycle events:

Each callback receives a single data Hash (keys include `:event`, `:token`,
`:scheme`, `:credential`, plus `:error` for `:refresh_failure` and `:cache_key`
for `:invalidated`).

```ruby
# Register a callback for token refresh
token_manager.on(:refresh_success) do |data|
  # data[:token] is the new token
end

# Register a callback for token refresh failure
token_manager.on(:refresh_failure) do |data|
  # data[:error] is the failure
end

# Register a callback for approaching expiration
token_manager.on(:before_expiry) do |data|
  # data[:token] is approaching expiry
end

# Register a callback for token invalidation
token_manager.on(:invalidated) do |data|
  # data[:cache_key] is the invalidated key
end
```

## Advanced Configuration

### Custom Token Store

```ruby
# Create a custom token store
class CustomTokenStore
  def store(key, token)
    # Store the token
  end
  
  def get(key)
    # Retrieve the token
  end
  
  def clear(key)
    # Clear the token
  end
end

# Use the custom token store
token_store = CustomTokenStore.new
token_manager = Legate::Auth::TokenManager.new(token_store)
```

### Background Token Refresh

```ruby
# Enable background token refresh
token_manager = Legate::Auth::TokenManager.new(token_store, {
  background_refresh: true
})

# This will refresh tokens in a background thread
```

## Best Practices

1. **Minimize Token Requests**: Cache tokens until they're close to expiration
2. **Handle Refresh Failures**: Implement retry logic with backoff
3. **Secure Storage**: Tokens are not encrypted by `TokenStore`; apply the opt-in `Legate::Auth::Encryption` module if you need at-rest encryption
4. **Revoke Unused Tokens**: Explicitly revoke tokens when they're no longer needed
5. **Monitor Token Usage**: Track token usage for security auditing

## Troubleshooting

### Token Refresh Failures

If token refresh fails, check:
- The refresh token hasn't expired or been revoked
- The token endpoint is accessible
- The client credentials are still valid
- Network connectivity to the provider

### Token Storage Issues

If tokens aren't being properly stored:
- Verify the session service is properly initialized and passed to `TokenStore.new`
- Ensure session persistence between requests
- If you added opt-in `Legate::Auth::Encryption`, verify the key is consistent across instances

### Performance Considerations

- Token refresh can add latency to requests
- Use the refresh buffer to refresh tokens before they expire
- Consider background refresh for critical applications

## Next Steps

- [OAuth2 Authentication](./oauth2) - Learn more about OAuth2 authentication flows
- [Service Account Authentication](./service_account) - Use service accounts for server-to-server authentication
- [Secure Credential Storage](./secure_storage) - Best practices for credential security

## Related Topics
- [OAuth2 Authentication](./oauth2) - Learn more about OAuth2 authentication flows
- [Service Account Authentication](./service_account) - Use service accounts for server-to-server authentication
- [Secure Credential Storage](./secure_storage) - Best practices for credential security 