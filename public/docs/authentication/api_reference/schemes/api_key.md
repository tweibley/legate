# Legate::Auth::Schemes::ApiKey

The `ApiKey` class implements API key authentication, one of the simplest and most common methods for authenticating API requests. This scheme handles the inclusion of API keys in requests via headers, query parameters, or other methods.

## Overview

API key authentication is a straightforward authentication method where a single secret key is included in API requests. The API key scheme in Legate Ruby provides flexible options for configuring how and where the API key is included in requests.

## Class Methods

### `new`

Creates a new API key authentication scheme. The constructor takes **no arguments** — the API key's location (`header`, `query`, or `cookie`) and parameter/header name are read from the **credential** at apply time (via its `location:` and `name:` attributes), not from the scheme.

**Examples:**

```ruby
# Create an API key scheme (no constructor arguments)
scheme = Legate::Auth::Schemes::ApiKey.new

# Location and name live on the credential, not the scheme:
credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key',
  location: 'header',      # 'header' (default), 'query', or 'cookie'
  name: 'X-API-Key'        # header/parameter/cookie name (default: 'X-API-Key')
)
```

## Instance Methods

### `scheme_type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:api_key`

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::ApiKey.new
scheme.scheme_type  # => :api_key
```

### `apply_to_request`

Applies API key authentication to a request by adding the API key to the appropriate location.

**Parameters:**
- `request` (Hash): The request to authenticate
- `credential` (Legate::Auth::ExchangedCredential): The exchanged credential containing the API key

**Returns:**
- Hash: The authenticated request with the API key in the specified location

**Examples:**

```ruby
# Create an API key credential and exchange it
credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

scheme = Legate::Auth::Schemes::ApiKey.new
token = scheme.exchange_token(credential)

# Apply to a request
request = { headers: {} }
authenticated = scheme.apply_to_request(request, token)
```

### `exchange_token`

Exchanges a credential for an authentication token. For API keys, this simply wraps the API key in an ExchangedCredential.

**Parameters:**
- `credential` (Legate::Auth::Credential): The credential to exchange

**Returns:**
- Legate::Auth::ExchangedCredential: The exchanged token

**Examples:**

```ruby
# Create an API key credential
credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

# Exchange for a token
scheme = Legate::Auth::Schemes::ApiKey.new
token = scheme.exchange_token(credential)

# The exchanged credential stores the key under :api_key (not :access_token)
puts token[:api_key]        # => "my-api-key"
puts token[:access_token]   # => nil
```

### `to_h`

Converts the scheme to a hash representation.

**Returns:**
- Hash: A hash representation of the scheme configuration

## Usage Examples

### Basic API Key Authentication

```ruby
# Create an API key scheme
scheme = Legate::Auth::Schemes::ApiKey.new

# Create a credential with the API key
credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

# Exchange for a token
token = scheme.exchange_token(credential)

# Apply to a request
request = { headers: {} }
authenticated = scheme.apply_to_request(request, token)
```

### With Token Manager

```ruby
# Create an API key scheme
scheme = Legate::Auth::Schemes::ApiKey.new

# Create a credential with the API key
credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

# Use with token manager
token_store = Legate::Auth::TokenStore.new(session_service)
token_manager = Legate::Auth::TokenManager.new(token_store)

# Get a token (this will create and store the ExchangedCredential)
token = token_manager.get_token(scheme, credential)
```

### With Environment Variables

```ruby
# Create a credential with the API key from an environment variable
credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'ENV:API_KEY'
)
```

## Security Considerations

- API keys are essentially long-term passwords and should be protected accordingly
- Always use HTTPS for all API requests that include API keys
- Restrict API key permissions to only what's necessary
- Implement proper access controls for API keys
- Rotate API keys regularly
- Consider using more advanced authentication schemes (OAuth2, OIDC) for sensitive operations

## See Also

- [Legate::Auth::Credential](../credential)
- [Legate::Auth::ExchangedCredential](../exchanged_credential)
- [Legate::Auth::Scheme](../scheme)
- [Legate::Auth::TokenManager](../token_manager)
