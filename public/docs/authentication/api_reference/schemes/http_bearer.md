# Legate::Auth::Schemes::HTTPBearer

The `HTTPBearer` class implements the HTTP Bearer authentication scheme, which uses a bearer token to authenticate API requests. This is one of the simpler authentication schemes, used when you already have a bearer token. It is also available via the `HttpBearer` alias.

## Overview

The HTTP Bearer authentication scheme is specified in [RFC 6750](https://tools.ietf.org/html/rfc6750) and is a widely used method for API authentication. It works by including an access token in the `Authorization` header of HTTP requests with the prefix `Bearer`.

## Class Methods

### `new`

Creates a new HTTP Bearer authentication scheme.

**Parameters:**
- None required

**Examples:**

```ruby
# Create a basic HTTP Bearer scheme
scheme = Legate::Auth::Schemes::HTTPBearer.new
```

## Instance Methods

### `scheme_type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:http_bearer`

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::HTTPBearer.new
scheme.scheme_type  # => :http_bearer
```

### `apply_to_request`

Applies bearer token authentication to a request by adding the token to the Authorization header.

**Parameters:**
- `request` (Hash): The request to authenticate
- `credential` (Legate::Auth::ExchangedCredential): The exchanged credential containing the bearer token

**Returns:**
- Hash: The authenticated request with bearer token in the Authorization header

**Examples:**

```ruby
# Create a bearer token credential and exchange it
credential = Legate::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'my-bearer-token'
)

scheme = Legate::Auth::Schemes::HTTPBearer.new
token = scheme.exchange_token(credential)

# Apply to a request
request = { headers: {} }
authenticated = scheme.apply_to_request(request, token)
puts authenticated[:headers]['Authorization']  # => "Bearer my-bearer-token"
```

### `exchange_token`

Exchanges a credential for an authentication token. For HTTP Bearer, this simply wraps the bearer token in an ExchangedCredential.

**Parameters:**
- `credential` (Legate::Auth::Credential): The credential to exchange

**Returns:**
- Legate::Auth::ExchangedCredential: The exchanged token

**Examples:**

```ruby
# Create a bearer token credential
credential = Legate::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'my-bearer-token'
)

# Exchange for a token
scheme = Legate::Auth::Schemes::HTTPBearer.new
token = scheme.exchange_token(credential)

# The token is a wrapped version of the bearer token
puts token[:access_token]  # => "my-bearer-token"
```

### `to_h`

Converts the scheme to a hash representation.

**Returns:**
- Hash: A hash representation of the scheme configuration

## Usage Examples

### Basic Authentication

```ruby
# Create an HTTP Bearer scheme
scheme = Legate::Auth::Schemes::HTTPBearer.new

# Create a credential with the bearer token
credential = Legate::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'my-bearer-token'
)

# Exchange for a token
token = scheme.exchange_token(credential)

# Apply to a request
request = { headers: {} }
authenticated = scheme.apply_to_request(request, token)
puts authenticated[:headers]['Authorization']  # => "Bearer my-bearer-token"
```

### With Token Manager

```ruby
# Create an HTTP Bearer scheme
scheme = Legate::Auth::Schemes::HTTPBearer.new

# Create a credential with the bearer token
credential = Legate::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'my-bearer-token'
)

# Use with token manager
token_store = Legate::Auth::TokenStore.new(session_service)
token_manager = Legate::Auth::TokenManager.new(token_store)

# Get a token (this will create and store the ExchangedCredential)
token = token_manager.get_token(scheme, credential)
```

### With Environment Variables

```ruby
# Create a credential with the bearer token from environment
credential = Legate::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: ENV['API_BEARER_TOKEN']
)
```

## Security Considerations

- Bearer tokens should be treated like passwords and kept secure
- Always use HTTPS when transmitting bearer tokens
- Implement proper token lifecycle management, including expiration and revocation
- Consider using short-lived tokens to minimize the risk of token leakage

## See Also

- [Legate::Auth::Credential](../credential)
- [Legate::Auth::ExchangedCredential](../exchanged_credential)
- [Legate::Auth::Scheme](../scheme)
- [Legate::Auth::TokenManager](../token_manager)
