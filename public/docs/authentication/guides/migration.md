# Migrating from Earlier Versions

## Overview

This guide helps you migrate your ADK Ruby applications from earlier versions to the current version, focusing on authentication-related changes.

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
gem 'adk-ruby', '~> 0.4.0'

# New (v0.5.x)
gem 'adk-ruby', '~> 0.5.0'
```

#### Step 2: Migrate API Key Authentication

```ruby
# Old (v0.4.x)
toolset = Adk::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  api_key: ENV['API_KEY']
)

# New (v0.5.x)
api_key_scheme = Adk::Auth::Schemes::APIKey.new(
  name: 'api_key',
  in: :header,
  header_name: 'X-API-Key'
)

api_key_credential = Adk::Auth::Credential.new(
  api_key: ENV['API_KEY']
)

toolset = Adk::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  auth_scheme: api_key_scheme,
  auth_credential: api_key_credential
)
```

#### Step 3: Migrate OAuth2 Authentication

```ruby
# Old (v0.4.x)
toolset = Adk::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  oauth2_client_id: ENV['OAUTH2_CLIENT_ID'],
  oauth2_client_secret: ENV['OAUTH2_CLIENT_SECRET'],
  oauth2_auth_url: 'https://auth.example.com/authorize',
  oauth2_token_url: 'https://auth.example.com/token',
  oauth2_scopes: ['read', 'write']
)

# New (v0.5.x)
oauth2_scheme = Adk::Auth::Schemes::OAuth2.new(
  auth_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['read', 'write']
)

oauth2_credential = Adk::Auth::Credential.new(
  client_id: ENV['OAUTH2_CLIENT_ID'],
  client_secret: ENV['OAUTH2_CLIENT_SECRET']
)

toolset = Adk::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  auth_scheme: oauth2_scheme,
  auth_credential: oauth2_credential
)
```

#### Step 4: Migrate Custom Function Tools

```ruby
# Old (v0.4.x)
class MyApiTool < Adk::Tool::FunctionTool
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
class MyApiTool < Adk::Tool::FunctionTool
  def initialize
    api_key_scheme = Adk::Auth::Schemes::APIKey.new(
      name: 'api_key',
      in: :header,
      header_name: 'X-API-Key'
    )
    
    api_key_credential = Adk::Auth::Credential.new(
      api_key: ENV['API_KEY']
    )
    
    super(
      name: 'my_api_tool',
      description: 'A tool that interacts with an API',
      auth_scheme: api_key_scheme,
      auth_credential: api_key_credential
    )
  end
  
  def call(context, **params)
    connection = Adk::Auth.create_connection(
      'https://api.example.com',
      scheme: context.auth_scheme,
      credential: context.auth_credential
    )
    
    response = connection.get(path: '/data')
    JSON.parse(response.body)
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
def call(context, **params)
  # Try to get valid tokens
  tokens = context.get_valid_tokens(refresh: true)
  
  unless tokens
    # No valid tokens, check for auth response
    auth_response = context.get_auth_response
    
    if auth_response
      # Process the auth response to get tokens
      tokens = {
        access_token: auth_response.access_token,
        refresh_token: auth_response.refresh_token,
        expires_at: auth_response.expires_at
      }
      
      # Store the tokens for future use
      context.store_tokens(tokens)
    else
      # Request authentication
      auth_config = Adk::Auth::Config.new(
        scheme: context.auth_scheme,
        credential: context.auth_credential
      )
      context.request_auth(auth_config)
      # Execution will yield here if interactive authentication is required
      return { status: 'authentication_required' }
    end
  end
  
  # Make authenticated API request
  connection = Adk::Auth.create_connection(
    'https://api.example.com',
    scheme: context.auth_scheme,
    credential: context.auth_credential
  )
  
  response = connection.get(path: '/data')
  JSON.parse(response.body)
end
```

#### Step 6: Migrate Session Storage

```ruby
# Old (v0.4.x)
session_service = Adk::SessionService::Redis.new(
  redis_url: ENV['REDIS_URL']
)

# New (v0.5.x)
session_service = Adk::SessionService::Redis.new(
  redis_url: ENV['REDIS_URL']
)

# Create a token store for authentication
token_store = Adk::Auth::TokenStore.new(
  session_service: session_service
)

# Create a token manager
token_manager = Adk::Auth::TokenManager.new(
  token_store: token_store,
  scheme: oauth2_scheme
)
```

## Migrating from v0.3.x

### Major Changes from v0.3.x to v0.5.x

Version 0.3.x had limited authentication support, using direct API key or OAuth2 configuration. Version 0.5.x introduces a comprehensive authentication system with the following improvements:

1. **Unified Authentication**: A single authentication system for all authentication methods
2. **Improved Security**: Secure storage and encryption of credentials and tokens
3. **Interactive Flows**: Support for OAuth2, OIDC, and custom interactive flows
4. **Token Lifecycle**: Automatic token refresh and invalidation
5. **Middleware Support**: Excon middleware for authentication

### Migration Steps

#### Step 1: Update Dependencies

```ruby
# Old (v0.3.x)
gem 'adk-ruby', '~> 0.3.0'

# New (v0.5.x)
gem 'adk-ruby', '~> 0.5.0'
```

#### Step 2: Migrate Basic Authentication

```ruby
# Old (v0.3.x)
toolset = Adk::Tool::OpenAPIToolset.new(
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

bearer_scheme = Adk::Auth::Schemes::HTTPBearer.new

bearer_credential = Adk::Auth::Credential.new(
  bearer_token: "Basic #{basic_token}"
)

toolset = Adk::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  auth_scheme: bearer_scheme,
  auth_credential: bearer_credential
)
```

#### Step 3: Migrate API Key Authentication

```ruby
# Old (v0.3.x)
toolset = Adk::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  auth: {
    type: 'api_key',
    in: 'header',
    name: 'X-API-Key',
    value: ENV['API_KEY']
  }
)

# New (v0.5.x)
api_key_scheme = Adk::Auth::Schemes::APIKey.new(
  name: 'api_key',
  in: :header,
  header_name: 'X-API-Key'
)

api_key_credential = Adk::Auth::Credential.new(
  api_key: ENV['API_KEY']
)

toolset = Adk::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  auth_scheme: api_key_scheme,
  auth_credential: api_key_credential
)
```

## Additional Migration Notes

### Environment Variables

The new authentication system encourages the use of environment variables for credential values:

```ruby
# Reference environment variables directly
oauth2_credential = Adk::Auth::Credential.new(
  client_id_env: 'OAUTH2_CLIENT_ID',
  client_secret_env: 'OAUTH2_CLIENT_SECRET'
)
```

### Web UI Integration

If you're using the ADK Web UI, you'll need to update your authentication integration:

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
  connection = Adk::Auth.create_connection(
    'https://api.example.com',
    scheme: scheme,
    credential: credential
  )
  # ...
end
```

## Troubleshooting Migration Issues

### Missing Authentication Scheme

If you encounter errors about missing authentication scheme:

```
Adk::Auth::Error::SchemeNotConfiguredError: No authentication scheme configured
```

Make sure you've created and passed the appropriate scheme:

```ruby
# Create the appropriate scheme
api_key_scheme = Adk::Auth::Schemes::APIKey.new(
  name: 'api_key',
  in: :header,
  header_name: 'X-API-Key'
)

# Pass it to the tool/toolset
toolset = Adk::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  auth_scheme: api_key_scheme,
  auth_credential: api_key_credential
)
```

### Missing Authentication Credential

If you encounter errors about missing credentials:

```
Adk::Auth::Error::CredentialNotConfiguredError: No authentication credential configured
```

Make sure you've created and passed the appropriate credential:

```ruby
# Create the appropriate credential
api_key_credential = Adk::Auth::Credential.new(
  api_key: ENV['API_KEY']
)

# Pass it to the tool/toolset
toolset = Adk::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  auth_scheme: api_key_scheme,
  auth_credential: api_key_credential
)
```

### Token Refresh Failures

If you encounter token refresh failures after migration:

```
Adk::Auth::Error::TokenRefreshError: Failed to refresh token
```

Make sure you've configured the token manager correctly:

```ruby
# Create a token store
token_store = Adk::Auth::TokenStore.new(
  session_service: session_service
)

# Create a token manager
token_manager = Adk::Auth::TokenManager.new(
  token_store: token_store,
  scheme: oauth2_scheme
)
```

## Related Topics
- [Authentication Configuration](./configuration)
- [Token Lifecycle Management](./token_lifecycle)
- [Secure Credential Storage](./secure_storage)
- [OAuth2 Authentication](./oauth2)
- [OpenID Connect](./oidc)
- [Service Account Authentication](./service_account) 