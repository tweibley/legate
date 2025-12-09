# Adk::Auth::Schemes::OAuth2

The `OAuth2` class implements the OAuth 2.0 authentication scheme, which is a widely adopted industry-standard protocol for authorization. This scheme handles the complex token exchange flows between your application, users, and OAuth 2.0 providers.

## Overview

OAuth 2.0 is an authorization framework that enables third-party applications to obtain limited access to a user's account on an HTTP service. It works by delegating user authentication to the service that hosts the user's account and authorizing third-party applications to access that account.

## Class Methods

### `new`

Creates a new OAuth 2.0 authentication scheme.

**Parameters:**
- `client_id` (String, optional): The OAuth 2.0 client ID
- `client_secret` (String, optional): The OAuth 2.0 client secret
- `authorize_url` (String, optional): The authorization endpoint URL
- `token_url` (String, optional): The token endpoint URL
- `redirect_uri` (String, optional): The redirect URI for the OAuth flow
- `scopes` (Array<String>, optional): The OAuth scopes to request
- `flow` (Symbol, optional): The OAuth flow to use (default: `:authorization_code`)
- `kwargs` (Hash, optional): Additional parameters for the authentication scheme

**Examples:**

```ruby
# Create a basic OAuth2 scheme for authorization code flow
scheme = Adk::Auth::Schemes::OAuth2.new(
  client_id: 'ENV:OAUTH_CLIENT_ID',
  client_secret: 'ENV:OAUTH_CLIENT_SECRET',
  authorize_url: 'https://provider.com/oauth2/authorize',
  token_url: 'https://provider.com/oauth2/token',
  redirect_uri: 'http://localhost:3000/oauth2/callback',
  scopes: ['profile', 'email']
)

# Create an OAuth2 scheme for client credentials flow
scheme = Adk::Auth::Schemes::OAuth2.new(
  client_id: 'ENV:OAUTH_CLIENT_ID',
  client_secret: 'ENV:OAUTH_CLIENT_SECRET',
  token_url: 'https://provider.com/oauth2/token',
  flow: :client_credentials
)
```

## Instance Methods

### `type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:oauth2`

**Examples:**

```ruby
scheme = Adk::Auth::Schemes::OAuth2.new
scheme.type  # => :oauth2
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
# Create a valid OAuth2 credential
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# Validate the credential
scheme = Adk::Auth::Schemes::OAuth2.new
scheme.validate_credential(credential)  # => true
```

### `authorize_url`

Generates the authorization URL for the OAuth 2.0 flow.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential containing client information
- `params` (Hash, optional): Additional parameters for the authorization URL
  - `state` (String, optional): State parameter for CSRF protection
  - `scope` (String, Array<String>, optional): OAuth scopes to request
  - `redirect_uri` (String, optional): Override the default redirect URI
  - `response_type` (String, optional): OAuth response type (default: "code")

**Returns:**
- String: The authorization URL for the OAuth 2.0 flow

**Examples:**

```ruby
# Create OAuth2 credential
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# Generate an authorization URL
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorize_url: 'https://provider.com/oauth2/authorize',
  redirect_uri: 'http://localhost:3000/oauth2/callback',
  scopes: ['profile', 'email']
)
auth_url = scheme.authorize_url(
  credential, 
  state: SecureRandom.hex(16)
)

# Redirect the user to this URL
puts "Please visit: #{auth_url}"
```

### `authenticate`

Authenticates a request using the OAuth 2.0 access token.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential containing the access token
- `params` (Hash, optional): Additional parameters for the authentication process
  - `headers` (Hash, optional): HTTP headers to modify
  - `request` (Object, optional): The request object to authenticate

**Returns:**
- Hash: The authenticated request with access token in the Authorization header

**Examples:**

```ruby
# Assuming we have a credential with a valid token
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  access_token: 'access-token-from-oauth-provider'
)

# Authenticate a request
scheme = Adk::Auth::Schemes::OAuth2.new
result = scheme.authenticate(credential, headers: {})

# The result contains the updated headers
puts result[:headers]['Authorization']  # => "Bearer access-token-from-oauth-provider"
```

### `exchange_token`

Exchanges an authorization code or client credentials for access and refresh tokens.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential containing client information
- `params` (Hash, optional): Additional parameters for the token exchange
  - `code` (String, required for authorization code flow): The authorization code from the OAuth provider
  - `redirect_uri` (String, optional): The redirect URI used in the authorization request
  - `grant_type` (String, optional): The grant type to use (default: based on flow)
  - `code_verifier` (String, optional): The code verifier for PKCE

**Returns:**
- Adk::Auth::ExchangedCredential: The exchanged tokens

**Examples:**

```ruby
# Create OAuth2 credential
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# Exchange authorization code for tokens
scheme = Adk::Auth::Schemes::OAuth2.new(
  token_url: 'https://provider.com/oauth2/token',
  redirect_uri: 'http://localhost:3000/oauth2/callback'
)
token = scheme.exchange_token(credential, code: 'authorization-code-from-callback')

# The token contains OAuth2 tokens
puts token[:access_token]   # => "access-token"
puts token[:refresh_token]  # => "refresh-token" (if granted)
puts token[:expires_in]     # => 3600 (seconds until expiration)
```

### `refresh_token`

Refreshes an expired OAuth 2.0 access token using the refresh token.

**Parameters:**
- `credential` (Adk::Auth::Credential): The original credential
- `token` (Adk::Auth::ExchangedCredential): The token to refresh

**Returns:**
- Adk::Auth::ExchangedCredential: The refreshed token

**Examples:**

```ruby
# Create a credential
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# Assume we have a token with a refresh token
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'expired-access-token',
  refresh_token: 'valid-refresh-token',
  expires_at: Time.now - 60  # Expired 60 seconds ago
)

# Refresh the token
scheme = Adk::Auth::Schemes::OAuth2.new(
  token_url: 'https://provider.com/oauth2/token'
)
refreshed_token = scheme.refresh_token(credential, token)

# The refreshed token has a new access token
puts refreshed_token[:access_token]  # => "new-access-token"
```

## Usage Examples

### Authorization Code Flow

```ruby
require 'securerandom'

# Step 1: Create the OAuth2 scheme
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorize_url: 'https://provider.com/oauth2/authorize',
  token_url: 'https://provider.com/oauth2/token',
  redirect_uri: 'http://localhost:3000/oauth2/callback',
  scopes: ['profile', 'email']
)

# Step 2: Set up credential with client details
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['OAUTH_CLIENT_ID'],
  client_secret: ENV['OAUTH_CLIENT_SECRET']
)

# Step 3: Generate state for security
state = SecureRandom.hex(16)

# Store this securely in session
session[:oauth_state] = state

# Step 4: Generate authorization URL and redirect user
auth_url = scheme.authorize_url(credential, state: state)
redirect_to auth_url

# Step 5: Handle the callback (in a separate route handler)
def callback
  # Verify state parameter to protect against CSRF
  if params[:state] != session[:oauth_state]
    return render plain: "Invalid state parameter"
  end
  
  # Exchange code for tokens
  token = scheme.exchange_token(credential, code: params[:code])
  
  # Store tokens for future API calls
  token_store = Adk::Auth::TokenStore.new(session)
  token_store.put('oauth2_token', token)
  
  redirect_to '/dashboard'
end
```

### Client Credentials Flow

```ruby
# Create an OAuth2 scheme for client credentials flow
scheme = Adk::Auth::Schemes::OAuth2.new(
  token_url: 'https://provider.com/oauth2/token',
  flow: :client_credentials,
  scopes: ['api:read', 'api:write']
)

# Create a credential with client details
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['API_CLIENT_ID'],
  client_secret: ENV['API_CLIENT_SECRET']
)

# Exchange client credentials for token (no user interaction required)
token = scheme.exchange_token(credential)

# Use the token for API calls
headers = {}
authenticated = scheme.authenticate(token, headers: headers)

# Make authenticated request
require 'net/http'
uri = URI('https://api.example.com/resources')
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Get.new(uri)
request['Authorization'] = authenticated[:headers]['Authorization']

response = http.request(request)
```

### Resource Owner Password Credentials Flow

```ruby
# Create an OAuth2 scheme for password flow
scheme = Adk::Auth::Schemes::OAuth2.new(
  token_url: 'https://provider.com/oauth2/token',
  flow: :password
)

# Create a credential with client details and user credentials
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET'],
  username: 'user@example.com',
  password: 'user-password'
)

# Exchange password for token
token = scheme.exchange_token(credential)

# Store token for future use
token_store = Adk::Auth::TokenStore.new(session)
token_store.put('user_token', token)
```

### Using with Token Manager

```ruby
# Create OAuth2 scheme and credential
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorize_url: 'https://provider.com/oauth2/authorize',
  token_url: 'https://provider.com/oauth2/token',
  redirect_uri: 'http://localhost:3000/oauth2/callback'
)

credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'ENV:OAUTH_CLIENT_ID',
  client_secret: 'ENV:OAUTH_CLIENT_SECRET'
)

# Use with token manager for automatic token management
token_store = Adk::Auth::TokenStore.new(session)
token_manager = Adk::Auth::TokenManager.new(token_store)

# Try to get an existing token, or start the flow to get a new one
token_key = 'oauth2_token'
if token_manager.has_token?(token_key)
  # Use existing token (will auto-refresh if expired)
  token = token_manager.get_token(scheme, credential, token_key)
else
  # Need to start an authentication flow
  auth_url = scheme.authorize_url(credential, state: SecureRandom.hex(16))
  # (redirect user to auth_url, and process in callback)
end
```

## OAuth 2.0 Flow Types

### Authorization Code Flow

Best for server-side applications where client credentials can be kept secure:

```ruby
scheme = Adk::Auth::Schemes::OAuth2.new(
  flow: :authorization_code,  # Default flow
  authorize_url: 'https://provider.com/oauth2/authorize',
  token_url: 'https://provider.com/oauth2/token',
  redirect_uri: 'http://localhost:3000/oauth2/callback'
)
```

### Client Credentials Flow

For machine-to-machine authentication where no user is involved:

```ruby
scheme = Adk::Auth::Schemes::OAuth2.new(
  flow: :client_credentials,
  token_url: 'https://provider.com/oauth2/token'
)
```

### Password Flow

For trusted applications that can collect user credentials:

```ruby
scheme = Adk::Auth::Schemes::OAuth2.new(
  flow: :password,
  token_url: 'https://provider.com/oauth2/token'
)
```

### Authorization Code with PKCE

For public clients like mobile apps or single-page applications:

```ruby
# Generate code verifier and challenge
code_verifier = SecureRandom.urlsafe_base64(64)
code_challenge = Base64.urlsafe_encode64(
  Digest::SHA256.digest(code_verifier),
  padding: false
)

scheme = Adk::Auth::Schemes::OAuth2.new(
  flow: :authorization_code,
  authorize_url: 'https://provider.com/oauth2/authorize',
  token_url: 'https://provider.com/oauth2/token',
  redirect_uri: 'http://localhost:3000/oauth2/callback'
)

# Generate authorization URL with PKCE
auth_url = scheme.authorize_url(
  credential,
  code_challenge: code_challenge,
  code_challenge_method: 'S256'
)

# Later in the callback, use the code_verifier
token = scheme.exchange_token(
  credential,
  code: params[:code],
  code_verifier: code_verifier
)
```

## Provider-Specific Configurations

### Google

```ruby
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorize_url: 'https://accounts.google.com/o/oauth2/auth',
  token_url: 'https://oauth2.googleapis.com/token',
  redirect_uri: 'http://localhost:3000/oauth2/google/callback',
  scopes: ['profile', 'email', 'https://www.googleapis.com/auth/calendar']
)
```

### Microsoft Azure

```ruby
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorize_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
  token_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
  redirect_uri: 'http://localhost:3000/oauth2/microsoft/callback',
  scopes: ['User.Read', 'Calendars.Read']
)
```

### GitHub

```ruby
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorize_url: 'https://github.com/login/oauth/authorize',
  token_url: 'https://github.com/login/oauth/access_token',
  redirect_uri: 'http://localhost:3000/oauth2/github/callback',
  scopes: ['user', 'repo']
)
```

## Security Considerations

- Always use HTTPS for all OAuth 2.0 communications
- Store client secrets securely and never expose them in client-side code
- Implement state parameter validation to prevent CSRF attacks
- Use PKCE extension for public clients to prevent authorization code interception
- Store tokens securely, preferably encrypted at rest
- Implement proper token lifecycle management, including expiration and revocation
- Request only the scopes that your application needs (principle of least privilege)

## Advantages and Limitations

### Advantages
- Industry-standard protocol with wide support
- Enables secure delegated access to resources
- Supports various authentication flows for different use cases
- Separates authentication from authorization
- Supports token refresh without re-authentication

### Limitations
- More complex than simple authentication schemes
- Requires proper security implementation to be secure
- Some flows are vulnerable to certain attacks if not properly implemented

## See Also

- [Adk::Auth::Credential](../credential)
- [Adk::Auth::ExchangedCredential](../exchanged_credential)
- [Adk::Auth::Scheme](../scheme)
- [Adk::Auth::TokenManager](../token_manager)
- [OAuth2 Troubleshooting](../../troubleshooting/oauth2_issues) 