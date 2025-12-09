# Adk::Auth::Credential

The `Credential` class represents authentication credentials required by different authentication schemes. It handles different types of credentials such as API keys, OAuth2 client credentials, service account keys, and HTTP Bearer tokens.

## Overview

A credential contains the initial authentication information needed to begin an authentication flow or to directly authenticate requests. It can handle different credential types and supports environment variable resolution for sensitive values.

## Class Constants

- `VALID_TYPES`: Valid credential types - `:api_key`, `:oauth2`, `:oidc`, `:service_account`, `:google_service_account`, `:http_bearer`
- `ENV_PREFIX`: Prefix for environment variable references (`'ENV:'`)

## Class Methods

### `new`

Creates a new credential instance.

**Parameters:**
- `auth_type` (Symbol): The type of authentication (:api_key, :oauth2, :oidc, :service_account, :http_bearer)
- `kwargs` (Hash): Additional attributes for the specific auth type

**Raises:**
- `Adk::Auth::CredentialError`: If the credential is invalid

**Examples:**

```ruby
# API Key credential
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

# OAuth2 credential
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# OAuth2 credential with environment variable
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'my-client-id',
  client_secret: 'ENV:MY_CLIENT_SECRET'
)

# Service Account credential
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: JSON.parse(File.read('service-account.json'))
)

# HTTP Bearer token
credential = Adk::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'my-bearer-token'
)
```

## Instance Methods

### `[]`

Gets an attribute value, optionally resolving environment variables.

**Parameters:**
- `name` (Symbol, String): The attribute name
- `resolve_env` (Boolean, optional): Whether to resolve environment variables (default: true)

**Returns:**
- The attribute value, or nil if not present

**Raises:**
- `Adk::Auth::EnvironmentVariableNotFoundError`: If an environment variable is not found

**Examples:**

```ruby
# Get a regular attribute
client_id = credential[:client_id]

# Get an attribute without resolving environment variables
raw_value = credential[:client_secret, resolve_env: false]

# Get an attribute with environment variable resolution (default)
resolved_value = credential[:client_secret]
```

### `[]=`

Sets an attribute value.

**Parameters:**
- `name` (Symbol, String): The attribute name
- `value` (Object): The attribute value

**Examples:**

```ruby
# Set an attribute
credential[:client_id] = 'new-client-id'

# Set an environment variable reference
credential[:client_secret] = 'ENV:NEW_CLIENT_SECRET'
```

### `to_h`

Converts the credential to a hash.

**Parameters:**
- `resolve_env` (Boolean, optional): Whether to resolve environment variables (default: false)

**Returns:**
- Hash: A hash representation of the credential

**Examples:**

```ruby
# Get hash representation without resolving environment variables
hash = credential.to_h

# Get hash representation with environment variables resolved
resolved_hash = credential.to_h(resolve_env: true)
```

### `has_attribute?`

Checks if the credential has an attribute.

**Parameters:**
- `name` (Symbol, String): The attribute name

**Returns:**
- Boolean: True if the attribute exists

**Examples:**

```ruby
# Check if an attribute exists
if credential.has_attribute?(:client_id)
  # Use the client_id
end
```

## Required Attributes by Type

Each credential type requires specific attributes:

| Type | Required Attributes | Description |
|------|---------------------|-------------|
| `:api_key` | `:api_key` | The API key for authentication |
| `:oauth2` | `:client_id` | The OAuth2 client ID |
| `:oidc` | `:client_id` | The OpenID Connect client ID |
| `:service_account` | `:service_account_key` or `:service_account_key_file` | The service account key or key file |
| `:google_service_account` | `:service_account_key` or `:service_account_key_file` | The Google service account key or key file |
| `:http_bearer` | `:bearer_token` | The Bearer token |

## Environment Variable Resolution

The Credential class supports referencing environment variables for sensitive values by prefixing the value with `ENV:`:

```ruby
# Reference an environment variable
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'my-client-id',
  client_secret: 'ENV:MY_CLIENT_SECRET'
)

# When accessing the attribute, the environment variable is resolved
secret = credential[:client_secret]  # Resolves to the value of ENV['MY_CLIENT_SECRET']
```

## Examples

### API Key Authentication

```ruby
# Standard API key
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key'
)

# API key from environment variable
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'ENV:API_KEY'
)

# API key with additional options
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'my-api-key',
  location: 'header',          # Where to place the API key
  name: 'X-Custom-API-Key'     # Name of the header or parameter
)
```

### OAuth2 Authentication

```ruby
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'ENV:OAUTH_CLIENT_ID',
  client_secret: 'ENV:OAUTH_CLIENT_SECRET'
)
```

### Service Account Authentication

```ruby
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: JSON.parse(File.read('service-account.json'))
)
```

## Security Considerations

- Always use environment variables (`ENV:` prefix) for sensitive values like client secrets and API keys
- Never hardcode sensitive credentials in your code
- The `resolve_env: false` option can be useful for logging to avoid exposing sensitive values

## See Also

- [Adk::Auth::Scheme](./scheme)
- [Adk::Auth::ExchangedCredential](./exchanged_credential)
- [Adk::Auth::TokenManager](./token_manager) 