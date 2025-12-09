# Adk::Auth::Schemes::ApiKey

The `ApiKey` class implements API key authentication, one of the simplest and most common methods for authenticating API requests. This scheme handles the inclusion of API keys in requests via headers, query parameters, or other methods.

## Overview

API key authentication is a straightforward authentication method where a single secret key is included in API requests. The API key scheme in ADK Ruby provides flexible options for configuring how and where the API key is included in requests.

## Class Methods

### `new`

Creates a new API key authentication scheme.

**Parameters:**
- `location` (Symbol, String, optional): Where to place the API key. Options: `:header`, `:query`, `:path`, `:body`. Default: `:header`
- `name` (String, optional): The name of the header or parameter to use. Default: `"X-Api-Key"`
- `prefix` (String, optional): A prefix to add to the API key value
- `kwargs` (Hash, optional): Additional parameters for the authentication scheme

**Examples:**

```ruby
# Create a basic API key scheme (header-based)
scheme = Adk::Auth::Schemes::ApiKey.new

# Create an API key scheme for query parameter placement
scheme = Adk::Auth::Schemes::ApiKey.new(
  location: :query,
  name: 'api_key'
)

# Create an API key scheme with a custom header
scheme = Adk::Auth::Schemes::ApiKey.new(
  location: :header,
  name: 'Authorization',
  prefix: 'ApiKey '
)
```

## Instance Methods

### `type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:api_key`

**Examples:**

```ruby
scheme = Adk::Auth::Schemes::ApiKey.new
scheme.type  # => :api_key
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
# Create a valid API key credential
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

# Validate the credential
scheme = Adk::Auth::Schemes::ApiKey.new
scheme.validate_credential(credential)  # => true
```

### `authenticate`

Authenticates a request by adding the API key to the appropriate location.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential containing the API key
- `params` (Hash, optional): Additional parameters for the authentication process
  - `headers` (Hash, optional): HTTP headers to modify
  - `query` (Hash, optional): Query parameters to modify
  - `body` (Hash, optional): Request body to modify (for body-based API keys)
  - `request` (Object, optional): The request object to authenticate

**Returns:**
- Hash: The authenticated request with the API key in the specified location

**Examples:**

```ruby
# Create an API key credential
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

# Authenticate a request with header-based API key
scheme = Adk::Auth::Schemes::ApiKey.new(location: :header, name: 'X-Api-Key')
result = scheme.authenticate(credential, headers: {})

# The result contains the updated headers
puts result[:headers]['X-Api-Key']  # => "my-api-key"

# Authenticate a request with query-based API key
scheme = Adk::Auth::Schemes::ApiKey.new(location: :query, name: 'api_key')
result = scheme.authenticate(credential, query: {})

# The result contains the updated query parameters
puts result[:query]['api_key']  # => "my-api-key"
```

### `exchange_token`

Exchanges a credential for an authentication token. For API keys, this simply wraps the API key in an ExchangedCredential.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential to exchange
- `params` (Hash, optional): Additional parameters for the token exchange

**Returns:**
- Adk::Auth::ExchangedCredential: The exchanged token

**Examples:**

```ruby
# Create an API key credential
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

# Exchange for a token
scheme = Adk::Auth::Schemes::ApiKey.new
token = scheme.exchange_token(credential)

# The token is a wrapped version of the API key
puts token[:access_token]  # => "my-api-key"
puts token.expired?        # => false (API key tokens don't expire)
```

## Usage Examples

### Header-Based API Key

```ruby
# Create a header-based API key scheme
scheme = Adk::Auth::Schemes::ApiKey.new(
  location: :header,
  name: 'X-Api-Key'
)

# Create a credential with the API key
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

# Authenticate a request
headers = {}
authenticated = scheme.authenticate(credential, headers: headers)

# The authenticated headers contain the API key
puts authenticated[:headers]['X-Api-Key']  # => "my-api-key"
```

### Query Parameter API Key

```ruby
# Create a query parameter-based API key scheme
scheme = Adk::Auth::Schemes::ApiKey.new(
  location: :query,
  name: 'api_key'
)

# Create a credential with the API key
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

# Authenticate a request
query = {}
authenticated = scheme.authenticate(credential, query: query)

# The authenticated query contains the API key
puts authenticated[:query]['api_key']  # => "my-api-key"
```

### Custom Authorization Header

```ruby
# Create an API key scheme that uses the Authorization header
scheme = Adk::Auth::Schemes::ApiKey.new(
  location: :header,
  name: 'Authorization',
  prefix: 'ApiKey '  # Will add this prefix to the API key
)

# Create a credential with the API key
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

# Authenticate a request
headers = {}
authenticated = scheme.authenticate(credential, headers: headers)

# The authenticated headers contain the Authorization header
puts authenticated[:headers]['Authorization']  # => "ApiKey my-api-key"
```

### With Token Manager

```ruby
# Create an API key scheme
scheme = Adk::Auth::Schemes::ApiKey.new

# Create a credential with the API key
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

# Use with token manager
token_store = Adk::Auth::TokenStore.new(session)
token_manager = Adk::Auth::TokenManager.new(token_store)

# Get a token (this will create and store the ExchangedCredential)
token = token_manager.get_token(scheme, credential)
```

### With Tool Configuration

```ruby
# Create an API key scheme
scheme = Adk::Auth::Schemes::ApiKey.new(
  location: :header,
  name: 'X-Api-Key'
)

# Create a credential with the API key from an environment variable
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY']
)

# Configure a tool with the scheme and credential
tool = Adk::Tools::SomeTool.new(
  auth_scheme: scheme,
  auth_credential: credential
)

# Use the tool - authentication happens automatically
result = tool.execute(params)
```

## API Key Placement Options

### Header-Based API Keys

```ruby
# Default is header-based with X-Api-Key header
scheme = Adk::Auth::Schemes::ApiKey.new

# Equivalent to
scheme = Adk::Auth::Schemes::ApiKey.new(
  location: :header,
  name: 'X-Api-Key'
)

# Custom header name
scheme = Adk::Auth::Schemes::ApiKey.new(
  location: :header,
  name: 'X-My-Custom-API-Key'
)
```

### Query Parameter API Keys

```ruby
# Add API key to query parameters
scheme = Adk::Auth::Schemes::ApiKey.new(
  location: :query,
  name: 'api_key'
)
```

### Request Body API Keys

```ruby
# Add API key to request body (for POST requests)
scheme = Adk::Auth::Schemes::ApiKey.new(
  location: :body,
  name: 'apiKey'
)
```

### Path Parameter API Keys

```ruby
# For APIs that require the API key in the path
# Note: You need to handle path template substitution in your request
scheme = Adk::Auth::Schemes::ApiKey.new(
  location: :path,
  name: 'api_key'
)
```

## Security Considerations

- API keys are essentially long-term passwords and should be protected accordingly
- Always use HTTPS for all API requests that include API keys
- Restrict API key permissions to only what's necessary
- Implement proper access controls for API keys
- Rotate API keys regularly
- Consider using more advanced authentication schemes (OAuth2, OIDC) for sensitive operations

## Advantages and Limitations

### Advantages
- Simple to implement and use
- No token exchange or refresh complexity
- Widely supported by API providers
- No token expiration to manage

### Limitations
- Cannot be easily revoked without changing the key
- Limited granularity for permissions (all-or-nothing access)
- No built-in user identity information
- No standard for key rotation or management

## See Also

- [Adk::Auth::Credential](../credential)
- [Adk::Auth::ExchangedCredential](../exchanged_credential)
- [Adk::Auth::Scheme](../scheme)
- [Adk::Auth::TokenManager](../token_manager)
- [API Key Authentication Guide](../../guides/api_key) 