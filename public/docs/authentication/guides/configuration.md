# Authentication Configuration

## Overview

This guide explains how to configure authentication in your ADK Ruby applications. Proper configuration is essential for successfully authenticating with external APIs and services.

## Configuration Components

Authentication in the ADK Ruby library involves configuring three main components:

1. **Authentication Scheme**: Defines how the API expects authentication (API Key, OAuth2, etc.)
2. **Authentication Credential**: Contains the initial information needed for authentication
3. **Tool Configuration**: Associates schemes and credentials with tools

## Authentication Schemes

Authentication schemes define the protocol and parameters for authenticating with an API.

### Available Schemes

```ruby
# API Key scheme
api_key_scheme = Adk::Auth::Schemes::APIKey.new(
  name: 'api_key',
  in: :header,
  header_name: 'X-API-Key'
)

# HTTP Bearer scheme
bearer_scheme = Adk::Auth::Schemes::HTTPBearer.new

# OAuth2 scheme
oauth2_scheme = Adk::Auth::Schemes::OAuth2.new(
  auth_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['read', 'write']
)

# OpenID Connect scheme
oidc_scheme = Adk::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://auth.example.com/.well-known/openid-configuration',
  scopes: ['openid', 'profile', 'email']
)

# Service Account scheme
service_account_scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://auth.example.com/token'
)

# Google Service Account scheme
google_service_account_scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/drive']
)
```

### Scheme Properties

Each scheme type has different configuration properties:

#### APIKey Scheme

| Property | Description | Default | Required |
|----------|-------------|---------|----------|
| `name` | Name of the API key parameter | 'api_key' | No |
| `in` | Location of the API key (`:header`, `:query`, `:cookie`) | `:header` | No |
| `header_name` | Header name when `in: :header` | 'X-API-Key' | No |
| `query_param_name` | Query parameter name when `in: :query` | 'api_key' | No |
| `cookie_name` | Cookie name when `in: :cookie` | 'api_key' | No |

#### HTTPBearer Scheme

The HTTPBearer scheme doesn't require any additional configuration properties.

#### OAuth2 Scheme

| Property | Description | Default | Required |
|----------|-------------|---------|----------|
| `auth_url` | Authorization endpoint URL | None | Yes |
| `token_url` | Token endpoint URL | None | Yes |
| `scopes` | List of OAuth2 scopes | [] | No |
| `auth_style` | Token endpoint authentication style (`:basic`, `:header`, `:body`) | `:basic` | No |
| `client_id_param` | Parameter name for client ID | 'client_id' | No |
| `client_secret_param` | Parameter name for client secret | 'client_secret' | No |
| `token_path` | Path to token endpoint | '/token' | No |

#### OpenIDConnect Scheme

| Property | Description | Default | Required |
|----------|-------------|---------|----------|
| `discovery_url` | OIDC discovery document URL | None | Yes |
| `scopes` | List of OIDC scopes | ['openid'] | No |
| `auth_style` | Token endpoint authentication style (`:basic`, `:header`, `:body`) | `:basic` | No |

#### ServiceAccount Scheme

| Property | Description | Default | Required |
|----------|-------------|---------|----------|
| `token_url` | Token endpoint URL | None | Yes |
| `auth_style` | Token endpoint authentication style (`:basic`, `:header`, `:body`) | `:basic` | No |
| `audience` | Service account token audience | None | No |

#### GoogleServiceAccount Scheme

| Property | Description | Default | Required |
|----------|-------------|---------|----------|
| `scopes` | List of Google API scopes | [] | Yes |
| `token_url` | Token endpoint URL | 'https://oauth2.googleapis.com/token' | No |
| `audience` | Service account token audience | None | No |

## Authentication Credentials

Authentication credentials contain the initial information needed to start authentication.

### Creating Credentials

```ruby
# API Key credential
api_key_credential = Adk::Auth::Credential.new(
  api_key: ENV['API_KEY']
)

# HTTP Bearer credential
bearer_credential = Adk::Auth::Credential.new(
  bearer_token: ENV['BEARER_TOKEN']
)

# OAuth2 credential
oauth2_credential = Adk::Auth::Credential.new(
  client_id: ENV['OAUTH2_CLIENT_ID'],
  client_secret: ENV['OAUTH2_CLIENT_SECRET']
)

# Service Account credential
service_account_credential = Adk::Auth::Credential.new(
  client_id: ENV['SERVICE_ACCOUNT_CLIENT_ID'],
  client_secret: ENV['SERVICE_ACCOUNT_CLIENT_SECRET']
)

# Google Service Account credential
google_service_account_credential = Adk::Auth::Credential.new(
  service_account_json: ENV['GOOGLE_SERVICE_ACCOUNT_JSON']
)
```

### Environment Variable References

You can reference environment variables directly in credential properties:

```ruby
# Reference environment variables directly
oauth2_credential = Adk::Auth::Credential.new(
  client_id_env: 'OAUTH2_CLIENT_ID',
  client_secret_env: 'OAUTH2_CLIENT_SECRET'
)
```

### Common Credential Properties

| Property | Description | Used With |
|----------|-------------|-----------|
| `api_key` | The API key value | API Key scheme |
| `api_key_env` | Environment variable name containing the API key | API Key scheme |
| `bearer_token` | The bearer token value | Bearer scheme |
| `bearer_token_env` | Environment variable name containing the bearer token | Bearer scheme |
| `client_id` | OAuth2/OIDC client ID | OAuth2, OIDC schemes |
| `client_id_env` | Environment variable name containing the client ID | OAuth2, OIDC schemes |
| `client_secret` | OAuth2/OIDC client secret | OAuth2, OIDC schemes |
| `client_secret_env` | Environment variable name containing the client secret | OAuth2, OIDC schemes |
| `service_account_json` | Service account JSON credentials | Service Account schemes |
| `service_account_json_env` | Environment variable containing service account JSON | Service Account schemes |
| `service_account_json_path` | Path to file containing service account JSON | Service Account schemes |

## Tool Configuration

### Configuring Toolsets

```ruby
# Configure an OpenAPI toolset with authentication
toolset = Adk::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  auth_scheme: oauth2_scheme,
  auth_credential: oauth2_credential
)
```

### Configuring Custom Tools

```ruby
# Configure a custom tool with authentication
class MyApiTool < Adk::Tool::FunctionTool
  def initialize
    super(
      name: 'my_api_tool',
      description: 'A tool that interacts with an API',
      auth_scheme: oauth2_scheme,
      auth_credential: oauth2_credential
    )
  end
  
  def call(context, **params)
    # Use authentication through the context
    # ...
  end
end
```

## Advanced Configuration

### Multiple Authentication Schemes

For APIs that support multiple authentication schemes, you can configure tools with different schemes:

```ruby
# API that supports both API Key and OAuth2
api_key_tool = MyApiTool.new(
  auth_scheme: api_key_scheme,
  auth_credential: api_key_credential
)

oauth2_tool = MyApiTool.new(
  auth_scheme: oauth2_scheme,
  auth_credential: oauth2_credential
)
```

### Token Store Configuration

Configure the token store for token management:

```ruby
# Create a token store
token_store = Adk::Auth::TokenStore.new(
  session_service: session_service
)

# Configure a token manager with the token store
token_manager = Adk::Auth::TokenManager.new(
  token_store: token_store,
  refresh_threshold: 300 # Refresh tokens 5 minutes before expiration
)
```

### HTTP Client Configuration

Configure Excon middleware for authentication:

```ruby
# Create middleware for authentication
middleware = Adk::Auth.create_middleware(
  scheme: oauth2_scheme,
  credential: oauth2_credential,
  token_store: token_store,
  max_retries: 3,
  backoff_strategy: :exponential
)

# Create a connection with the middleware
connection = Excon.new('https://api.example.com', 
  middlewares: [middleware])
```

Or use the connection helper:

```ruby
# Create an authenticated connection directly
connection = Adk::Auth.create_connection(
  'https://api.example.com',
  scheme: oauth2_scheme,
  credential: oauth2_credential,
  token_store: token_store
)
```

## Configuration Best Practices

1. **Use Environment Variables for Sensitive Values**: Always use environment variables for sensitive credentials like API keys, client secrets, and tokens
2. **Validate Configuration**: Verify your authentication configuration before making API requests
3. **Use HTTPS**: Always use HTTPS URLs for authentication endpoints
4. **Limit Scopes**: Request only the scopes your application needs
5. **Secure Storage**: Use encrypted token storage for sensitive tokens
6. **Token Lifecycle**: Configure appropriate token refresh thresholds
7. **Error Handling**: Implement proper error handling for authentication failures

## Related Topics
- [API Key Authentication](./api_key)
- [HTTP Bearer Authentication](./bearer)
- [OAuth2 Authentication](./oauth2)
- [OpenID Connect](./oidc)
- [Service Account Authentication](./service_account)
- [Token Lifecycle Management](./token_lifecycle)
- [Secure Credential Storage](./secure_storage) 