# Migrating from Earlier Versions

## Overview

This guide helps you migrate your Legate Ruby applications from earlier versions to the current version, focusing on authentication-related changes.

## Migrating from v0.4.x

### Breaking Changes

Version 0.5.0 introduced a new authentication system that replaces the previous authentication mechanisms. The following breaking changes were introduced:

1. **Unified Authentication System**: Replaced multiple authentication strategies with a single unified system
2. **Authentication Schemes**: Introduced the concept of authentication schemes to define how APIs expect credentials
3. **Token Management**: Added comprehensive token lifecycle management
4. **Interactive Authentication**: Implemented Fiber-based control flow for interactive authentication

### Migration Steps

#### Step 1: Update Dependencies

```ruby
# Old (v0.4.x)
gem 'legate', '~> 0.4.0'

# New (v0.5.x)
gem 'legate', '~> 0.5.0'
```

#### Step 2: Migrate API Key Authentication

```ruby
# Old (v0.4.x)
toolset = Legate::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  api_key: ENV['API_KEY']
)

# New (v0.5.x)
# ApiKey.new takes no arguments; location/name live on the credential
api_key_scheme = Legate::Auth::Schemes::ApiKey.new

api_key_credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY'],
  location: 'header',
  name: 'X-API-Key'
)

# Attach the scheme/credential to an outbound connection
connection = Legate::Auth.create_connection('https://api.example.com',
  scheme: api_key_scheme,
  credential: api_key_credential
)
```

#### Step 3: Migrate OAuth2 Authentication

```ruby
# Old (v0.4.x)
toolset = Legate::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  oauth2_client_id: ENV['OAUTH2_CLIENT_ID'],
  oauth2_client_secret: ENV['OAUTH2_CLIENT_SECRET'],
  oauth2_auth_url: 'https://auth.example.com/authorize',
  oauth2_token_url: 'https://auth.example.com/token',
  oauth2_scopes: ['read', 'write']
)

# New (v0.5.x) — note: authorization_url (not auth_url)
oauth2_scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['read', 'write']
)

oauth2_credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['OAUTH2_CLIENT_ID'],
  client_secret: ENV['OAUTH2_CLIENT_SECRET']
)

# Drive the flow via Config (build_authorization_uri / exchange_token)
config = Legate::Auth::Config.new(scheme: oauth2_scheme, credential: oauth2_credential)
```

#### Step 4: Migrate Custom Function Tools

```ruby
# Old (v0.4.x)
class MyApiTool < Legate::Tool::FunctionTool
  def call(context, **params)
    api_key = ENV['API_KEY']
    response = Excon.get(
      'https://api.example.com/data',
      headers: { 'X-API-Key' => api_key }
    )
    JSON.parse(response.body)
  end
end

# New (v0.5.x)
class MyApiTool < Legate::Tool
  tool_description 'A tool that interacts with an API'

  def perform_execution(params, context)
    api_key_scheme = Legate::Auth::Schemes::ApiKey.new
    api_key_credential = Legate::Auth::Credential.new(
      auth_type: :api_key,
      api_key: ENV['API_KEY'],
      location: 'header',
      name: 'X-API-Key'
    )

    connection = Legate::Auth.create_connection(
      'https://api.example.com',
      scheme: api_key_scheme,
      credential: api_key_credential
    )

    response = connection.get(path: '/data')
    { status: :success, result: JSON.parse(response.body) }
  end
end
```

#### Step 5: Migrate Interactive Authentication Flows

```ruby
# Old (v0.4.x)
def call(context, **params)
  oauth2_client = OAuth2::Client.new(
    ENV['OAUTH2_CLIENT_ID'],
    ENV['OAUTH2_CLIENT_SECRET'],
    site: 'https://auth.example.com',
    authorize_url: '/authorize',
    token_url: '/token'
  )
  
  if context.session[:oauth2_access_token]
    # Use cached token
    access_token = OAuth2::AccessToken.from_hash(
      oauth2_client,
      JSON.parse(context.session[:oauth2_access_token])
    )
  else
    # Request authorization
    auth_url = oauth2_client.auth_code.authorize_url(
      redirect_uri: 'http://localhost:8080/callback',
      scope: 'read write'
    )
    
    # Yield for user interaction
    auth_code = yield(auth_url)
    
    # Exchange code for token
    access_token = oauth2_client.auth_code.get_token(
      auth_code,
      redirect_uri: 'http://localhost:8080/callback'
    )
    
    # Cache the token
    context.session[:oauth2_access_token] = access_token.to_hash.to_json
  end
  
  # Use the token
  response = access_token.get('/api/data')
  JSON.parse(response.body)
end

# New (v0.5.x)
# Interactive flows are driven by Config (build the auth URI, then exchange the
# code) or, inside a tool, via context.with_authentication which yields the auth
# request to your application. A direct Config-based example:
def perform_execution(params, context)
  scheme = Legate::Auth::Schemes::OAuth2.new(
    authorization_url: 'https://auth.example.com/authorize',
    token_url: 'https://auth.example.com/token',
    scopes: %w[read write]
  )
  credential = Legate::Auth::Credential.new(
    auth_type: :oauth2,
    client_id: ENV['OAUTH2_CLIENT_ID'],
    client_secret: ENV['OAUTH2_CLIENT_SECRET']
  )

  config = Legate::Auth::Config.new(scheme: scheme, credential: credential)
  state = SecureRandom.hex(16)
  auth_uri = config.build_authorization_uri('http://localhost:8080/callback', state)

  # Yield the auth URI to the caller for the user to complete, then on the
  # callback set config.response_uri and exchange:
  # config.response_uri = '...callback?code=...&state=...'
  # token = scheme.exchange_token(config, credential)

  { status: :success, result: { auth_uri: auth_uri } }
end
```

#### Step 6: Migrate Session Storage

```ruby
# Sessions are now always in-memory (Redis session service has been removed)
session_service = Legate::SessionService::InMemory.new

# Create a token store for authentication (positional argument)
token_store = Legate::Auth::TokenStore.new(session_service)

# Create a token manager (positional token store; optional positional config Hash).
# The TokenManager does not take a scheme — the scheme is passed per call to
# get_token(scheme, credential).
token_manager = Legate::Auth::TokenManager.new(token_store)
```

## Migrating from v0.3.x

### Major Changes from v0.3.x to v0.5.x

Version 0.3.x had limited authentication support, using direct API key or OAuth2 configuration. Version 0.5.x introduces a comprehensive authentication system with the following improvements:

1. **Unified Authentication**: A single authentication system for all authentication methods
2. **Improved Security**: Scoped token storage, optional opt-in at-rest encryption, and SSRF-guarded auth URLs
3. **Interactive Flows**: Support for OAuth2, OIDC, and custom interactive flows
4. **Token Lifecycle**: Automatic token refresh and invalidation
5. **Middleware Support**: Excon middleware for authentication

### Migration Steps

#### Step 1: Update Dependencies

```ruby
# Old (v0.3.x)
gem 'legate', '~> 0.3.0'

# New (v0.5.x)
gem 'legate', '~> 0.5.0'
```

#### Step 2: Migrate Basic Authentication

```ruby
# Old (v0.3.x)
toolset = Legate::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  auth: {
    type: 'basic',
    username: ENV['USERNAME'],
    password: ENV['PASSWORD']
  }
)

# New (v0.5.x)
# For Basic Auth, use HTTP Bearer with Basic encoded token
require 'base64'
basic_token = Base64.strict_encode64("#{ENV['USERNAME']}:#{ENV['PASSWORD']}")

bearer_scheme = Legate::Auth::Schemes::HTTPBearer.new

bearer_credential = Legate::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: "Basic #{basic_token}"
)

connection = Legate::Auth.create_connection('https://api.example.com',
  scheme: bearer_scheme,
  credential: bearer_credential
)
```

#### Step 3: Migrate API Key Authentication

```ruby
# Old (v0.3.x)
toolset = Legate::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  auth: {
    type: 'api_key',
    in: 'header',
    name: 'X-API-Key',
    value: ENV['API_KEY']
  }
)

# New (v0.5.x) — ApiKey.new takes no args; location/name on the credential
api_key_scheme = Legate::Auth::Schemes::ApiKey.new

api_key_credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY'],
  location: 'header',
  name: 'X-API-Key'
)

connection = Legate::Auth.create_connection('https://api.example.com',
  scheme: api_key_scheme,
  credential: api_key_credential
)
```

## Additional Migration Notes

### Environment Variables

The new authentication system encourages the use of environment variables for credential values:

```ruby
# Reference environment variables with the ENV: prefix (no *_env attributes)
oauth2_credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'ENV:OAUTH2_CLIENT_ID',
  client_secret: 'ENV:OAUTH2_CLIENT_SECRET'
)
```

### Web UI Integration

If you're using the Legate Web UI, you'll need to update your authentication integration:

```ruby
# Old (v0.4.x)
get '/auth/callback' do
  code = params[:code]
  session[:auth_code] = code
  # Close popup window
  '<script>window.close();</script>'
end

# New (v0.5.x)
get '/auth/callback' do
  # Verify state parameter
  client_state = params[:state]
  server_state = session[:oauth2_state]
  halt 403, 'Invalid state parameter' unless client_state && client_state == server_state
  
  # Get the authorization code
  code = params[:code]
  halt 400, 'Missing authorization code' unless code
  
  # Store the authorization code and response URI
  session[:auth_code] = code
  session[:auth_response_uri] = request.url
  
  # Close the popup window and notify the parent window
  <<-HTML
    <script>
      window.opener.postMessage({ type: 'auth_callback', code: '#{code}' }, window.location.origin);
      window.close();
    </script>
  HTML
end
```

### Helper Migration

If you've created custom helpers for authentication, you'll need to update them:

```ruby
# Old (v0.4.x)
def authenticate_api_request(api_key)
  headers = { 'X-API-Key' => api_key }
  # ...
end

# New (v0.5.x)
def authenticate_api_request(scheme, credential)
  connection = Legate::Auth.create_connection(
    'https://api.example.com',
    scheme: scheme,
    credential: credential
  )
  # ...
end
```

## Troubleshooting Migration Issues

### Missing Authentication Scheme

If a scheme is misconfigured, validation raises a `Legate::Auth::SchemeValidationError`
(a subclass of `ConfigurationError`). Note the auth exception classes are flat under
`Legate::Auth` (e.g. `SchemeValidationError`, `CredentialError`, `TokenRefreshError`) —
there is no `Legate::Auth::Error::*` sub-namespace.

```
Legate::Auth::SchemeValidationError: Invalid authentication scheme configuration
```

Make sure you've created the scheme with the required arguments:

```ruby
# ApiKey.new takes no arguments; location/name live on the credential
api_key_scheme = Legate::Auth::Schemes::ApiKey.new
```

### Missing or Invalid Credential

A missing required attribute (or an invalid `auth_type`) raises
`Legate::Auth::CredentialError`:

```
Legate::Auth::CredentialError: Missing required attributes for api_key: api_key
```

Make sure you've created the credential with `auth_type:` and the required attributes:

```ruby
api_key_credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY']
)
```

### Token Refresh Failures

A failed refresh raises `Legate::Auth::TokenRefreshError`:

```
Legate::Auth::TokenRefreshError: Token refresh failed
```

Make sure you've configured the token store and manager correctly (positional args):

```ruby
# Create a token store and manager (positional arguments)
token_store = Legate::Auth::TokenStore.new(session_service)
token_manager = Legate::Auth::TokenManager.new(token_store)
```

## Related Topics
- [Authentication Configuration](./configuration)
- [Token Lifecycle Management](./token_lifecycle)
- [Secure Credential Storage](./secure_storage)
- [OAuth2 Authentication](./oauth2)
- [OpenID Connect](./oidc)
- [Service Account Authentication](./service_account) 