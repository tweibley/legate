# Adk::Auth::Schemes::HTTPBearer

The `HTTPBearer` class implements the HTTP Bearer authentication scheme, which uses a bearer token to authenticate API requests. This is one of the simpler authentication schemes, used when you already have a bearer token.

## Overview

The HTTP Bearer authentication scheme is specified in [RFC 6750](https://tools.ietf.org/html/rfc6750) and is a widely used method for API authentication. It works by including an access token in the `Authorization` header of HTTP requests with the prefix `Bearer`.

## Class Methods

### `new`

Creates a new HTTP Bearer authentication scheme.

**Parameters:**
- None

**Examples:**

```ruby
# Create a basic HTTP Bearer scheme
scheme = Adk::Auth::Schemes::HTTPBearer.new
```

## Instance Methods

### `type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:http_bearer`

**Examples:**

```ruby
scheme = Adk::Auth::Schemes::HTTPBearer.new
scheme.type  # => :http_bearer
```

### `validate_credential`

Validates that a credential is compatible with this scheme.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential to validate

**Returns:**
- Boolean: `true` if the credential is valid for this scheme

**Raises:**
- `Adk::Auth::AuthenticationError`: If the credential is invalid for this scheme

**Examples:**

```ruby
# Create a valid bearer token credential
credential = Adk::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'my-bearer-token'
)

# Validate the credential
scheme = Adk::Auth::Schemes::HTTPBearer.new
scheme.validate_credential(credential)  # => true
```

### `authenticate`

Authenticates a request using the provided bearer token.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential containing the bearer token
- `params` (Hash, optional): Additional parameters for the authentication process
  - `headers` (Hash, optional): HTTP headers to modify
  - `request` (Object, optional): The request object to authenticate

**Returns:**
- Hash: The authenticated request with bearer token in the Authorization header

**Examples:**

```ruby
# Create a bearer token credential
credential = Adk::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'my-bearer-token'
)

# Authenticate a request
scheme = Adk::Auth::Schemes::HTTPBearer.new
result = scheme.authenticate(credential, headers: {})

# The result contains the updated headers
puts result[:headers]['Authorization']  # => "Bearer my-bearer-token"
```

### `exchange_token`

Exchanges a credential for an authentication token. For HTTP Bearer, this simply wraps the bearer token in an ExchangedCredential.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential to exchange
- `params` (Hash, optional): Additional parameters for the token exchange

**Returns:**
- Adk::Auth::ExchangedCredential: The exchanged token

**Examples:**

```ruby
# Create a bearer token credential
credential = Adk::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'my-bearer-token'
)

# Exchange for a token
scheme = Adk::Auth::Schemes::HTTPBearer.new
token = scheme.exchange_token(credential)

# The token is a wrapped version of the bearer token
puts token[:access_token]  # => "my-bearer-token"
```

## Usage Examples

### Basic Authentication

```ruby
# Create an HTTP Bearer scheme
scheme = Adk::Auth::Schemes::HTTPBearer.new

# Create a credential with the bearer token
credential = Adk::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'my-bearer-token'
)

# Authenticate a request
headers = {}
authenticated = scheme.authenticate(credential, headers: headers)

# The authenticated headers contain the Authorization header
puts authenticated[:headers]['Authorization']  # => "Bearer my-bearer-token"
```

### With Token Manager

```ruby
# Create an HTTP Bearer scheme
scheme = Adk::Auth::Schemes::HTTPBearer.new

# Create a credential with the bearer token
credential = Adk::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'my-bearer-token'
)

# Use with token manager
token_store = Adk::Auth::TokenStore.new(session)
token_manager = Adk::Auth::TokenManager.new(token_store)

# Get a token (this will create and store the ExchangedCredential)
token = token_manager.get_token(scheme, credential)
```

### With Tool Configuration

```ruby
# Create an HTTP Bearer scheme
scheme = Adk::Auth::Schemes::HTTPBearer.new

# Create a credential with the bearer token
credential = Adk::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: ENV['API_BEARER_TOKEN']  # Use environment variable
)

# Configure a tool with the scheme and credential
tool = Adk::Tools::SomeTool.new(
  auth_scheme: scheme,
  auth_credential: credential
)

# Use the tool - authentication happens automatically
result = tool.execute(params)
```

## Security Considerations

- Bearer tokens should be treated like passwords and kept secure
- Always use HTTPS when transmitting bearer tokens
- Implement proper token lifecycle management, including expiration and revocation
- Consider using short-lived tokens to minimize the risk of token leakage

## Advantages and Limitations

### Advantages
- Simple and straightforward implementation
- Widely supported by API providers
- No complex token exchange process

### Limitations
- No built-in token refresh mechanism
- No standard way to revoke bearer tokens
- Lacks the advanced security features of OAuth2 or OpenID Connect

## See Also

- [Adk::Auth::Credential](../credential)
- [Adk::Auth::ExchangedCredential](../exchanged_credential)
- [Adk::Auth::Scheme](../scheme)
- [Adk::Auth::TokenManager](../token_manager) 