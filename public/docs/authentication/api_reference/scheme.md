# Adk::Auth::Scheme

The `Scheme` class serves as the abstract base class for all authentication schemes in the ADK Ruby library. It defines the interface and common functionality that all authentication schemes must implement.

## Overview

Authentication schemes represent different methods of authenticating API requests, such as API keys, OAuth2, OpenID Connect, or service accounts. The `Scheme` class provides a consistent interface for all these authentication methods, enabling the ADK to work with different authentication mechanisms in a unified way.

## Class Methods

### `new`

Creates a new instance of the authentication scheme.

**Parameters:**
- `kwargs` (Hash): Parameters specific to the authentication scheme

**Examples:**

```ruby
# This is an abstract class and shouldn't be instantiated directly
# Instead, use one of the concrete implementations:
scheme = Adk::Auth::Schemes::ApiKey.new
```

## Instance Methods

### `authenticate`

Authenticates a request based on the provided credential. This method must be implemented by concrete subclasses.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential to use for authentication
- `params` (Hash, optional): Additional parameters for the authentication process

**Returns:**
- A result object containing the authenticated request or authentication details

**Examples:**

```ruby
# This method is called internally by the ADK
# The implementation depends on the specific scheme
```

### `type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: The authentication scheme type (e.g., `:api_key`, `:oauth2`)

**Examples:**

```ruby
scheme = Adk::Auth::Schemes::ApiKey.new
scheme.type  # => :api_key
```

### `validate_credential`

Validates that a credential is compatible with this scheme. This method must be implemented by concrete subclasses.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential to validate

**Returns:**
- Boolean: `true` if the credential is valid for this scheme

**Raises:**
- `Adk::Auth::AuthenticationError`: If the credential is invalid for this scheme

**Examples:**

```ruby
# This method is called internally by the ADK
# The implementation depends on the specific scheme
```

### `exchange_token`

Exchanges a credential for an authentication token. This method must be implemented by concrete subclasses that support token exchange.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential to exchange
- `params` (Hash, optional): Additional parameters for the token exchange

**Returns:**
- Adk::Auth::ExchangedCredential: The exchanged token

**Examples:**

```ruby
# This method is called internally by the ADK
# The implementation depends on the specific scheme
```

### `refresh_token`

Refreshes an expired token. This method must be implemented by concrete subclasses that support token refresh.

**Parameters:**
- `credential` (Adk::Auth::Credential): The original credential
- `token` (Adk::Auth::ExchangedCredential): The token to refresh

**Returns:**
- Adk::Auth::ExchangedCredential: The refreshed token

**Examples:**

```ruby
# This method is called internally by the ADK
# The implementation depends on the specific scheme
```

### `revoke_token`

Revokes a token. This method must be implemented by concrete subclasses that support token revocation.

**Parameters:**
- `credential` (Adk::Auth::Credential): The original credential
- `token` (Adk::Auth::ExchangedCredential): The token to revoke

**Examples:**

```ruby
# This method is called internally by the ADK
# The implementation depends on the specific scheme
```

### `generate_auth_config`

Generates an authentication configuration for interactive authentication flows. This method must be implemented by concrete subclasses that support interactive authentication.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential to use
- `callback_url` (String, optional): The callback URL for the authentication flow
- `params` (Hash, optional): Additional parameters for the authentication configuration

**Returns:**
- Adk::Auth::Config: The authentication configuration

**Examples:**

```ruby
# This method is called internally by the ADK
# The implementation depends on the specific scheme
```

### `exchange_auth_response`

Exchanges an authentication response for a token in interactive authentication flows. This method must be implemented by concrete subclasses that support interactive authentication.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential to use
- `auth_response` (Hash): The authentication response from the authentication provider
- `params` (Hash, optional): Additional parameters for the exchange

**Returns:**
- Adk::Auth::ExchangedCredential: The exchanged token

**Examples:**

```ruby
# This method is called internally by the ADK
# The implementation depends on the specific scheme
```

## Authentication Flow Types

The `Scheme` class supports different types of authentication flows:

1. **Non-Interactive Authentication**:
   - Direct authentication using API keys or bearer tokens
   - No user interaction required
   - Implemented by schemes like `ApiKey` and `HttpBearer`

2. **Token-Based Authentication**:
   - Uses tokens for authentication
   - May include token exchange, refresh, and revocation
   - Implemented by schemes like `OAuth2`, `OpenIDConnect`, and `ServiceAccount`

3. **Interactive Authentication**:
   - Requires user interaction to complete authentication
   - Uses `generate_auth_config` and `exchange_auth_response` methods
   - Implemented by schemes like `OAuth2` and `OpenIDConnect`

## Concrete Implementations

The ADK Ruby library includes the following concrete implementations of `Scheme`:

- [Adk::Auth::Schemes::ApiKey](./schemes/api_key.md): For API key authentication
- [Adk::Auth::Schemes::HttpBearer](./schemes/http_bearer.md): For HTTP Bearer token authentication
- [Adk::Auth::Schemes::OAuth2](./schemes/oauth2.md): For OAuth2 authentication
- [Adk::Auth::Schemes::OpenIDConnect](./schemes/oidc.md): For OpenID Connect authentication
- [Adk::Auth::Schemes::ServiceAccount](./schemes/service_account.md): For service account authentication
- [Adk::Auth::Schemes::GoogleServiceAccount](./schemes/google_service_account.md): For Google service account authentication

## Extension Points

To create a custom authentication scheme, extend the `Scheme` class and implement the required methods:

```ruby
class CustomScheme < Adk::Auth::Scheme
  def type
    :custom
  end

  def validate_credential(credential)
    unless credential.auth_type == :custom && credential[:custom_token]
      raise Adk::Auth::AuthenticationError, "Invalid credential for CustomScheme"
    end
    true
  end

  def authenticate(credential, params = {})
    validate_credential(credential)
    # Implement authentication logic
  end
end
```

## See Also

- [Adk::Auth::Credential](./credential.md)
- [Adk::Auth::ExchangedCredential](./exchanged_credential.md)
- [Adk::Auth::Config](./config.md)
- [Adk::Auth::TokenManager](./token_manager.md) 