# Legate::Auth::Scheme

The `Scheme` class serves as the abstract base class for all authentication schemes in the Legate Ruby library. It defines the interface and common functionality that all authentication schemes must implement.

## Overview

Authentication schemes represent different methods of authenticating API requests, such as API keys, OAuth2, OpenID Connect, or service accounts. The `Scheme` class provides a consistent interface for all these authentication methods, enabling the Legate to work with different authentication mechanisms in a unified way.

## Class Methods

### `new`

Creates a new instance of the authentication scheme.

**Parameters:**
- `kwargs` (Hash): Parameters specific to the authentication scheme

**Examples:**

```ruby
# This is an abstract class and shouldn't be instantiated directly
# Instead, use one of the concrete implementations:
scheme = Legate::Auth::Schemes::ApiKey.new
```

## Instance Methods

### `scheme_type`

Returns the type of the authentication scheme. This method must be implemented by concrete subclasses.

**Returns:**
- Symbol: The authentication scheme type (e.g., `:api_key`, `:oauth2`)

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::ApiKey.new
scheme.scheme_type  # => :api_key
```

### `apply_to_request`

Applies authentication to a request based on the provided credential. This method must be implemented by concrete subclasses.

**Parameters:**
- `request` (Hash): The request to authenticate
- `credential` (Legate::Auth::ExchangedCredential): The credential to use for authentication

**Returns:**
- Hash: The modified request with authentication applied

**Examples:**

```ruby
# This method is called internally by the Legate
# The implementation depends on the specific scheme
```

### `supports_refresh?`

Returns whether this scheme supports token refresh.

**Returns:**
- Boolean: `true` if the scheme supports token refresh

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::OAuth2.new(token_url: 'https://example.com/token')
scheme.supports_refresh?  # => true (if refresh is supported)
```

### `exchange_token`

Exchanges a credential for an authentication token. This method must be implemented by concrete subclasses that support token exchange.

**Parameters:**
- `credential` (Legate::Auth::Credential): The credential to exchange

**Returns:**
- Legate::Auth::ExchangedCredential: The exchanged token

**Examples:**

```ruby
# This method is called internally by the Legate
# The implementation depends on the specific scheme
```

### `refresh_token`

Refreshes an expired token. This method must be implemented by concrete subclasses that support token refresh.

**Parameters:**
- `token` (Legate::Auth::ExchangedCredential): The token to refresh
- `credential` (Legate::Auth::Credential): The original credential

**Returns:**
- Legate::Auth::ExchangedCredential: The refreshed token

**Examples:**

```ruby
# This method is called internally by the Legate
# The implementation depends on the specific scheme
```

### `revoke_token`

Revokes a token. This method must be implemented by concrete subclasses that support token revocation.

**Parameters:**
- `token` (Legate::Auth::ExchangedCredential): The token to revoke
- `credential` (Legate::Auth::Credential): The original credential

**Examples:**

```ruby
# This method is called internally by the Legate
# The implementation depends on the specific scheme
```

### `validate!`

Validates the scheme configuration. Raises an error if the configuration is invalid.

**Raises:**
- `Legate::Auth::SchemeValidationError`: If the scheme configuration is invalid

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://example.com/authorize',
  token_url: 'https://example.com/token'
)
scheme.validate!  # Raises if configuration is incomplete
```

### `build_authorization_uri`

Builds an authorization URI for interactive authentication flows. This method must be implemented by concrete subclasses that support interactive authentication.

**Parameters:**
- `config` (Legate::Auth::Config): The authentication configuration
- `redirect_uri` (String, optional): The redirect URI for the authentication flow
- `state` (String, optional): The state parameter for CSRF protection

**Returns:**
- String: The authorization URI

**Examples:**

```ruby
# This method is called internally by the Legate
# The implementation depends on the specific scheme
```

### `authentication_error?`

Checks if an HTTP response indicates an authentication error.

**Parameters:**
- `response` (Object): The HTTP response to check

**Returns:**
- Boolean: `true` if the response indicates an authentication error

**Examples:**

```ruby
# This method is called internally by the Legate
# Used by ExconMiddleware to detect auth failures for retry
```

### `to_h`

Converts the scheme to a hash representation.

**Returns:**
- Hash: A hash representation of the scheme

### `to_s`

Returns a string representation of the scheme.

**Returns:**
- String: A string representation of the scheme

## Authentication Flow Types

The `Scheme` class supports different types of authentication flows:

1. **Non-Interactive Authentication**:
   - Direct authentication using API keys or bearer tokens
   - No user interaction required
   - Implemented by schemes like `ApiKey` and `HTTPBearer`

2. **Token-Based Authentication**:
   - Uses tokens for authentication
   - May include token exchange, refresh, and revocation
   - Implemented by schemes like `OAuth2`, `OpenIDConnect`, and `ServiceAccount`

3. **Interactive Authentication**:
   - Requires user interaction to complete authentication
   - Uses `build_authorization_uri` for generating the auth URI
   - Implemented by schemes like `OAuth2` and `OpenIDConnect`

## Concrete Implementations

The Legate Ruby library includes the following concrete implementations of `Scheme`:

- [Legate::Auth::Schemes::ApiKey](./schemes/api_key): For API key authentication
- [Legate::Auth::Schemes::HTTPBearer](./schemes/http_bearer): For HTTP Bearer token authentication
- [Legate::Auth::Schemes::OAuth2](./schemes/oauth2): For OAuth2 authentication
- [Legate::Auth::Schemes::OpenIDConnect](./schemes/openid_connect): For OpenID Connect authentication
- [Legate::Auth::Schemes::ServiceAccount](./schemes/service_account): For service account authentication

## Extension Points

To create a custom authentication scheme, extend the `Scheme` class and implement the required methods:

```ruby
class CustomScheme < Legate::Auth::Scheme
  def scheme_type
    :custom
  end

  def apply_to_request(request, credential)
    request[:headers] ||= {}
    request[:headers]['Authorization'] = "Custom #{credential[:access_token]}"
    request
  end

  def exchange_token(credential)
    Legate::Auth::ExchangedCredential.new(
      auth_type: :custom,
      access_token: credential[:custom_token]
    )
  end
end
```

## See Also

- [Legate::Auth::Credential](./credential)
- [Legate::Auth::ExchangedCredential](./exchanged_credential)
- [Legate::Auth::Config](./config)
- [Legate::Auth::TokenManager](./token_manager)
