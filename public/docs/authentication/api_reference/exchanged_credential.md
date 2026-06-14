# Legate::Auth::ExchangedCredential

The `ExchangedCredential` class represents authentication tokens obtained through credential exchange (e.g., OAuth2 access tokens, service account tokens). It provides a consistent interface for handling different types of tokens and their associated metadata.

## Overview

After authenticating with an authentication scheme, a credential is exchanged for a token. The `ExchangedCredential` class encapsulates this token along with additional information like token type, expiration time, and refresh tokens.

## Class Methods

### `new`

Creates a new exchanged credential (token) instance.

**Parameters:**
- `auth_type` (Symbol, required keyword): The type of authentication (e.g., `:oauth2`, `:service_account`)
- `access_token` (String, required keyword): The access token
- `refresh_token` (String, optional keyword): The refresh token (default: nil)
- `token_type` (String, optional keyword): The type of token (default: 'Bearer')
- `expires_in` (Integer, optional keyword): Seconds until expiration (default: nil)
- `id_token` (String, optional keyword): The ID token for OIDC flows (default: nil)
- `provider_id` (String, optional keyword): The provider identifier (default: nil)
- `**attributes` (Hash): Additional attributes specific to the token type

**Examples:**

```ruby
# Create an OAuth2 token
token = Legate::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token',
  expires_in: 3600,
  token_type: 'Bearer'
)

# Create a service account token
token = Legate::Auth::ExchangedCredential.new(
  auth_type: :service_account,
  access_token: 'your-access-token',
  expires_in: 3600
)

# Create an OIDC token with id_token
token = Legate::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token',
  id_token: 'jwt-id-token',
  expires_in: 3600
)
```

### `from_h`

Creates an ExchangedCredential from a hash representation.

**Parameters:**
- `hash` (Hash): The hash to create the credential from

**Returns:**
- Legate::Auth::ExchangedCredential: A new ExchangedCredential instance

**Examples:**

```ruby
token = Legate::Auth::ExchangedCredential.from_h(saved_token_hash)
```

## Instance Methods

### `[]` (accessor)

Gets an attribute from the token.

**Parameters:**
- `name` (Symbol, String): The attribute name

**Returns:**
- Object: The attribute value, or nil if not present

**Examples:**

```ruby
token = Legate::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token'
)

access_token = token[:access_token]
refresh_token = token[:refresh_token]
```

### `to_h`

Converts the token to a hash.

**Returns:**
- Hash: A hash representation of the token

**Examples:**

```ruby
token = Legate::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token',
  expires_in: 3600
)

token_hash = token.to_h
# => {auth_type: :oauth2, access_token: "your-access-token", refresh_token: "your-refresh-token", ...}
```

### `with`

Returns a new ExchangedCredential with updated attributes.

**Parameters:**
- `attrs` (Hash): The attributes to update

**Returns:**
- Legate::Auth::ExchangedCredential: A new instance with the updated attributes

**Examples:**

```ruby
new_token = token.with(access_token: 'new-access-token', expires_in: 7200)
```

### `expired?`

Checks if the token is expired.

**Parameters:**
- `buffer_seconds` (Integer, optional): Buffer time in seconds before actual expiration (default: 30)

**Returns:**
- Boolean: `true` if the token is expired or will expire within the buffer time

**Examples:**

```ruby
token = Legate::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  expires_in: 3600
)

# Check if expired (with default 30-second buffer)
puts token.expired?
# => false

# Check if expires within the next 5 minutes
puts token.expired?(300)
# => false (if more than 5 minutes remaining)
```

### `refreshable?`

Checks if the token can be refreshed (i.e., has a refresh token).

**Returns:**
- Boolean: `true` if the token has a refresh token and can be refreshed

**Examples:**

```ruby
token = Legate::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token'
)

puts token.refreshable?
# => true

token_without_refresh = Legate::Auth::ExchangedCredential.new(
  auth_type: :api_key,
  access_token: 'your-api-key'
)

puts token_without_refresh.refreshable?
# => false
```

### `id_token_claims`

Decodes and returns the claims from the ID token (for OIDC tokens).

**Returns:**
- Hash: The decoded ID token claims, or nil if no ID token is present

**Examples:**

```ruby
token = Legate::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  id_token: 'jwt-id-token'
)

claims = token.id_token_claims
puts claims['sub']    # => "user-id"
puts claims['email']  # => "user@example.com"
```

## Common Token Attributes

Different token types have different attributes, but some common ones include:

| Attribute | Description | Token Types |
|-----------|-------------|------------|
| `access_token` | The access token used for authentication | All |
| `refresh_token` | Token used to refresh the access token | OAuth2, OIDC |
| `id_token` | JWT token containing user identity | OIDC |
| `expires_in` | Seconds until the token expires | OAuth2, OIDC, Service Account |
| `token_type` | Type of token (default: 'Bearer') | OAuth2, OIDC |
| `provider_id` | The provider identifier | Any |

## Working with Token Expiration

Managing token expiration is a common task:

```ruby
token = Legate::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  expires_in: 3600
)

# Check if expired (30-second buffer by default)
if token.expired?
  # Token needs to be refreshed
else
  # Token is still valid
end

# Check if expiring soon (within 5 minutes)
if token.expired?(300)
  # Token will expire soon, consider refreshing
end
```

## Secure Token Storage

ExchangedCredential objects contain sensitive information and should be handled securely:

1. Never log the full token
2. Store tokens securely — note that `TokenStore` does not encrypt them; apply the opt-in [`Legate::Auth::Encryption`](./encryption) module yourself if at-rest encryption is required
3. Implement proper token lifecycle management

```ruby
# Example of secure logging
token = Legate::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token'
)

# Log safely (truncate sensitive values)
logger.info "Token type: #{token[:auth_type]}, " \
            "Access token: #{token[:access_token].to_s[0..5]}..."
```

## See Also

- [Legate::Auth::Credential](./credential)
- [Legate::Auth::Scheme](./scheme)
- [Legate::Auth::TokenManager](./token_manager)
