# Authentication Configuration

## Overview

This guide explains how to configure authentication in your Legate Ruby applications. Proper configuration is essential for successfully authenticating with external APIs and services.

## Configuration Components

Authentication in the Legate Ruby library involves configuring three main components:

1. **Authentication Scheme**: Defines how the API expects authentication (API Key, OAuth2, etc.)
2. **Authentication Credential**: Contains the initial information needed for authentication
3. **Tool Configuration**: Associates schemes and credentials with tools

## Authentication Schemes

Authentication schemes define the protocol and parameters for authenticating with an API.

### Available Schemes

```ruby
# API Key scheme (no constructor arguments — the key's location and name
# come from the credential at apply time)
api_key_scheme = Legate::Auth::Schemes::ApiKey.new

# HTTP Bearer scheme
bearer_scheme = Legate::Auth::Schemes::HTTPBearer.new

# OAuth2 scheme
oauth2_scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['read', 'write']
)

# OpenID Connect scheme
oidc_scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://auth.example.com/.well-known/openid-configuration',
  scopes: ['openid', 'profile', 'email']
)

# Service Account scheme
service_account_scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://auth.example.com/token'
)

# Google Service Account scheme
google_service_account_scheme = Legate::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/drive']
)
```

### Scheme Properties

Each scheme type has different configuration properties:

#### ApiKey Scheme

`ApiKey.new` takes **no constructor arguments**. The API key's location and name are read from the **credential** at apply time:

| Credential attribute | Description | Default |
|----------------------|-------------|---------|
| `location` | Location of the API key (`'header'`, `'query'`, `'cookie'`) | `'header'` |
| `name` | Header/parameter/cookie name | `'X-API-Key'` |

#### HTTPBearer Scheme

The HTTPBearer scheme doesn't require any additional configuration properties.

#### OAuth2 Scheme (constructor keyword arguments)

| Argument | Description | Default | Required |
|----------|-------------|---------|----------|
| `authorization_url` | Authorization endpoint URL | None | Yes (for interactive flows) |
| `token_url` | Token endpoint URL | None | Yes |
| `scopes` | List/space-string of OAuth2 scopes | [] | No |
| `use_pkce` | Whether to use PKCE | `true` | No |
| `additional_params` | Extra params for the authorization request | None | No |
| `revocation_url` | Token revocation endpoint URL | None | No |

#### OpenIDConnect Scheme (constructor keyword arguments)

Inherits all OAuth2 arguments, plus:

| Argument | Description | Default | Required |
|----------|-------------|---------|----------|
| `discovery_url` | OIDC discovery document URL | None | No (if endpoints given) |
| `jwks_url` | JSON Web Key Set URL | None | No |
| `userinfo_url` | UserInfo endpoint URL | None | No |
| `issuer` | Expected issuer | None | No |

#### ServiceAccount Scheme (constructor keyword arguments)

| Argument | Description | Default | Required |
|----------|-------------|---------|----------|
| `token_url` | Token endpoint URL | None | Yes |
| `audience` | Service account token audience | None | No |
| `scopes` | Requested scopes | [] | No |
| `token_lifetime` | JWT lifetime in seconds | 3600 | No |

#### GoogleServiceAccount Scheme (constructor keyword arguments)

| Argument | Description | Default | Required |
|----------|-------------|---------|----------|
| `scopes` | List of Google API scopes | None | No |
| `token_url` | Token endpoint URL | 'https://oauth2.googleapis.com/token' | No |
| `audience` | Service account token audience | token_url | No |
| `token_lifetime` | JWT lifetime in seconds | 3600 | No |

## Authentication Credentials

Authentication credentials contain the initial information needed to start authentication.

### Creating Credentials

Every credential requires an `auth_type:`.

```ruby
# API Key credential
api_key_credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY']
)

# HTTP Bearer credential
bearer_credential = Legate::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: ENV['BEARER_TOKEN']
)

# OAuth2 credential
oauth2_credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['OAUTH2_CLIENT_ID'],
  client_secret: ENV['OAUTH2_CLIENT_SECRET']
)

# Service Account credential (service_account_key is a raw JSON string)
service_account_credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: File.read('service-account.json')
)

# Google Service Account credential
google_service_account_credential = Legate::Auth::Credential.new(
  auth_type: :google_service_account,
  service_account_key: ENV['GOOGLE_SERVICE_ACCOUNT_JSON']  # raw JSON string
)
```

### Environment Variable References

The only mechanism for referencing environment variables is the `ENV:` prefix
inside a string value. There are no `*_env` attributes.

```ruby
# Reference environment variables with the ENV: prefix
oauth2_credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'ENV:OAUTH2_CLIENT_ID',
  client_secret: 'ENV:OAUTH2_CLIENT_SECRET'
)
```

### Common Credential Properties

| Property | Description | Used With |
|----------|-------------|-----------|
| `auth_type` | Required: `:api_key`, `:http_bearer`, `:oauth2`, `:oidc`, `:service_account`, `:google_service_account`, `:basic` | All |
| `api_key` | The API key value (use `'ENV:NAME'` to read from the environment) | API Key scheme |
| `location` | API key location: `'header'`, `'query'`, or `'cookie'` | API Key scheme |
| `name` | API key header/parameter/cookie name | API Key scheme |
| `bearer_token` | The bearer token value | Bearer scheme |
| `client_id` | OAuth2/OIDC client ID | OAuth2, OIDC schemes |
| `client_secret` | OAuth2/OIDC client secret | OAuth2, OIDC schemes |
| `service_account_key` | Service account JSON as a raw string (use `'ENV:NAME'` to read from the environment) | Service Account schemes |
| `service_account_key_file` | Path to a file containing the service account JSON | Service Account schemes |

## Using Authentication in Tools

Within a `Legate::Tool`, use the authentication helpers added to the
`ToolContext` (see [`ToolContextExtension`](../api_reference/tool_context_extension)):

```ruby
class MyApiTool < Legate::Tool
  tool_description 'A tool that interacts with an authenticated API'

  def perform_execution(params, context)
    context.with_authentication do
      connection = Legate::Auth.create_connection('https://api.example.com',
        scheme: oauth2_scheme,
        credential: oauth2_credential
      )
      response = connection.get(path: '/resource')
      { status: :success, result: response.body }
    end
  end
end
```

## Advanced Configuration

### Token Store Configuration

Configure the token store and manager (both take **positional** arguments):

```ruby
# Create a token store (positional session service)
token_store = Legate::Auth::TokenStore.new(session_service)

# Configure a token manager with the token store. Config is a positional Hash;
# the key is refresh_buffer (seconds before expiry to refresh), not refresh_threshold.
token_manager = Legate::Auth::TokenManager.new(token_store, {
  refresh_buffer: 300 # Refresh tokens 5 minutes before expiration
})
```

### HTTP Client Configuration

The simplest way to attach authentication to an Excon connection is the
connection helper, which wires up the middleware for you:

```ruby
# Create an authenticated connection directly
connection = Legate::Auth.create_connection(
  'https://api.example.com',
  scheme: oauth2_scheme,
  credential: oauth2_credential,
  token_store: token_store,
  max_retries: 3,
  backoff_strategy: :exponential
)
```

`Legate::Auth.create_middleware(scheme:, credential:, ...)` is also available
if you need to build the middleware instance yourself.

## Configuration Best Practices

1. **Use Environment Variables for Sensitive Values**: Always use environment variables for sensitive credentials like API keys, client secrets, and tokens
2. **Validate Configuration**: Verify your authentication configuration before making API requests
3. **Use HTTPS**: Always use HTTPS URLs for authentication endpoints
4. **Limit Scopes**: Request only the scopes your application needs
5. **Secure Storage**: Tokens are cached as plaintext in scoped state; apply the opt-in `Legate::Auth::Encryption` module yourself if you need at-rest encryption
6. **Token Lifecycle**: Configure an appropriate `refresh_buffer` on the `TokenManager`
7. **Error Handling**: Implement proper error handling for authentication failures

## Related Topics
- [API Key Authentication](./api_key)
- [HTTP Bearer Authentication](./bearer)
- [OAuth2 Authentication](./oauth2)
- [OpenID Connect](./oidc)
- [Service Account Authentication](./service_account)
- [Token Lifecycle Management](./token_lifecycle)
- [Secure Credential Storage](./secure_storage) 