# Adk::Auth::ExchangedCredential

The `ExchangedCredential` class represents authentication tokens obtained through credential exchange (e.g., OAuth2 access tokens, service account tokens). It provides a consistent interface for handling different types of tokens and their associated metadata.

## Overview

After authenticating with an authentication scheme, a credential is exchanged for a token. The `ExchangedCredential` class encapsulates this token along with additional information like token type, expiration time, and refresh tokens.

## Class Methods

### `new`

Creates a new exchanged credential (token) instance.

**Parameters:**
- `auth_type` (Symbol): The type of authentication (e.g., `:oauth2`, `:service_account`)
- `access_token` (String): The access token
- `kwargs` (Hash): Additional attributes specific to the token type

**Examples:**

```ruby
# Create an OAuth2 token
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token',
  expires_in: 3600,
  token_type: 'Bearer'
)

# Create a service account token
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :service_account,
  access_token: 'your-access-token',
  expires_in: 3600,
  project_id: 'your-project-id'
)
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
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token'
)

access_token = token[:access_token]
refresh_token = token[:refresh_token]
```

### `[]=` (setter)

Sets an attribute value.

**Parameters:**
- `name` (Symbol, String): The attribute name
- `value` (Object): The attribute value

**Examples:**

```ruby
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token'
)

token[:custom_attribute] = 'custom-value'
```

### `to_h`

Converts the token to a hash.

**Returns:**
- Hash: A hash representation of the token

**Examples:**

```ruby
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token',
  expires_in: 3600
)

token_hash = token.to_h
# => {auth_type: :oauth2, access_token: "your-access-token", refresh_token: "your-refresh-token", expires_in: 3600}
```

### `auth_type`

Returns the authentication type.

**Returns:**
- Symbol: The authentication type (e.g., `:oauth2`, `:service_account`)

**Examples:**

```ruby
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token'
)

puts token.auth_type
# => :oauth2
```

### `expires_at`

Returns the expiration time of the token.

**Returns:**
- Time: The expiration time, or nil if not applicable

**Examples:**

```ruby
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  expires_in: 3600  # Token expires in 1 hour
)

puts token.expires_at
# => 2023-06-15 14:30:00 +0000 (1 hour from creation time)
```

### `expired?`

Checks if the token is expired.

**Parameters:**
- `buffer_seconds` (Integer, optional): Buffer time in seconds (default: 0)

**Returns:**
- Boolean: `true` if the token is expired or will expire within the buffer time

**Examples:**

```ruby
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  expires_in: 3600  # Token expires in 1 hour
)

# Check if expired now
puts token.expired?
# => false

# Check if expires within the next 30 minutes (1800 seconds)
puts token.expired?(buffer_seconds: 1800)
# => false (if more than 30 minutes remaining)
# => true (if less than 30 minutes remaining)
```

### `refresh_token?`

Checks if the token has a refresh token.

**Returns:**
- Boolean: `true` if the token has a refresh token

**Examples:**

```ruby
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token'
)

puts token.refresh_token?
# => true
```

### `can_refresh?`

Checks if the token can be refreshed.

**Returns:**
- Boolean: `true` if the token can be refreshed

**Examples:**

```ruby
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token'
)

puts token.can_refresh?
# => true

token = Adk::Auth::ExchangedCredential.new(
  auth_type: :api_key,
  access_token: 'your-api-key'
)

puts token.can_refresh?
# => false
```

## Common Token Attributes

Different token types have different attributes, but some common ones include:

| Attribute | Description | Token Types |
|-----------|-------------|------------|
| `access_token` | The access token used for authentication | All |
| `refresh_token` | Token used to refresh the access token | OAuth2, OIDC |
| `id_token` | JWT token containing user identity | OIDC |
| `expires_in` | Seconds until the token expires | OAuth2, OIDC, Service Account |
| `token_type` | Type of token (e.g., 'Bearer') | OAuth2, OIDC |
| `scope` | Space-separated list of granted scopes | OAuth2, OIDC |

## Token-Type Specific Attributes

### OAuth2 / OpenID Connect

```ruby
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token',
  expires_in: 3600,
  token_type: 'Bearer',
  scope: 'profile email',
  id_token: 'jwt-id-token'  # For OpenID Connect
)
```

### Service Account

```ruby
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :service_account,
  access_token: 'your-access-token',
  expires_in: 3600,
  project_id: 'your-project-id',
  client_email: 'service-account@project-id.iam.gserviceaccount.com'
)
```

### API Key

```ruby
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :api_key,
  access_token: 'your-api-key',
  location: 'header',       # Where to place the API key
  name: 'X-API-Key'         # Name of the header or parameter
)
```

## Working with Token Expiration

Managing token expiration is a common task:

```ruby
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  expires_in: 3600
)

# Check if expired
if token.expired?
  # Token needs to be refreshed
else
  # Token is still valid
end

# Check if expiring soon (within 5 minutes)
if token.expired?(buffer_seconds: 300)
  # Token will expire soon, consider refreshing
end
```

## Secure Token Storage

ExchangedCredential objects contain sensitive information and should be handled securely:

1. Never log the full token
2. Store tokens securely (encrypted)
3. Implement proper token lifecycle management

```ruby
# Example of secure logging
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'your-access-token',
  refresh_token: 'your-refresh-token'
)

# Log safely (truncate sensitive values)
logger.info "Token type: #{token.auth_type}, " \
            "Access token: #{token[:access_token].to_s[0..5]}..., " \
            "Expires at: #{token.expires_at}"
```

## See Also

- [Adk::Auth::Credential](./credential.md)
- [Adk::Auth::Scheme](./scheme.md)
- [Adk::Auth::TokenManager](./token_manager.md) 