# Adk::Auth::Schemes::Oidc

The `Oidc` class implements the OpenID Connect (OIDC) authentication scheme, which provides a layer of identity verification on top of OAuth 2.0 protocols. It handles the secure authentication and authorization flow between your application and OIDC providers.

## Overview

OpenID Connect is a simple identity layer built on top of the OAuth 2.0 protocol. It allows clients to verify the identity of end-users based on the authentication performed by an authorization server, as well as to obtain basic profile information about the end-user in an interoperable and REST-like manner.

## Class Methods

### `new`

Creates a new OpenID Connect authentication scheme.

**Parameters:**
- `issuer` (String, optional): The OIDC issuer URL
- `client_id` (String, optional): The client ID for the OIDC provider
- `client_secret` (String, optional): The client secret for the OIDC provider
- `redirect_uri` (String, optional): The redirect URI for the OIDC flow
- `scopes` (Array<String>, optional): The OIDC scopes to request (default: ['openid', 'email', 'profile'])
- `discovery` (Boolean, optional): Whether to use OIDC discovery (default: true)
- `kwargs` (Hash, optional): Additional parameters for the authentication scheme

**Examples:**

```ruby
# Create a basic OIDC scheme with discovery
scheme = Adk::Auth::Schemes::Oidc.new(
  issuer: 'https://accounts.google.com',
  client_id: 'ENV:OIDC_CLIENT_ID',
  client_secret: 'ENV:OIDC_CLIENT_SECRET',
  redirect_uri: 'http://localhost:3000/auth/callback'
)

# With custom scopes
scheme = Adk::Auth::Schemes::Oidc.new(
  issuer: 'https://login.microsoftonline.com/tenant-id/v2.0',
  client_id: 'ENV:OIDC_CLIENT_ID',
  client_secret: 'ENV:OIDC_CLIENT_SECRET',
  redirect_uri: 'http://localhost:3000/auth/callback',
  scopes: ['openid', 'email', 'profile', 'offline_access']
)
```

## Instance Methods

### `type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:oidc`

**Examples:**

```ruby
scheme = Adk::Auth::Schemes::Oidc.new(issuer: 'https://accounts.google.com')
scheme.type  # => :oidc
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
# Create a valid OIDC credential
credential = Adk::Auth::Credential.new(
  auth_type: :oidc,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# Validate the credential
scheme = Adk::Auth::Schemes::Oidc.new(issuer: 'https://accounts.google.com')
scheme.validate_credential(credential)  # => true
```

### `authorize_url`

Generates the authorization URL for the OIDC flow.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential containing client information
- `params` (Hash, optional): Additional parameters for the authorization URL
  - `state` (String, optional): State parameter for CSRF protection
  - `nonce` (String, optional): Nonce parameter for replay protection
  - `prompt` (String, optional): Prompt parameter for the authorization request
  - `login_hint` (String, optional): Hint about the login identifier

**Returns:**
- String: The authorization URL for the OIDC flow

**Examples:**

```ruby
# Create OIDC credential
credential = Adk::Auth::Credential.new(
  auth_type: :oidc,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# Generate an authorization URL
scheme = Adk::Auth::Schemes::Oidc.new(
  issuer: 'https://accounts.google.com',
  redirect_uri: 'http://localhost:3000/auth/callback'
)
auth_url = scheme.authorize_url(
  credential, 
  state: SecureRandom.hex(16),
  nonce: SecureRandom.hex(16)
)

# Redirect the user to this URL
puts "Please visit: #{auth_url}"
```

### `authenticate`

Authenticates a request using the OIDC access token.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential containing the tokens
- `params` (Hash, optional): Additional parameters for the authentication process
  - `headers` (Hash, optional): HTTP headers to modify
  - `request` (Object, optional): The request object to authenticate

**Returns:**
- Hash: The authenticated request with access token in the Authorization header

**Examples:**

```ruby
# Assuming we have a credential with a valid token
credential = Adk::Auth::Credential.new(
  auth_type: :oidc,
  access_token: 'access-token-from-oidc-provider'
)

# Authenticate a request
scheme = Adk::Auth::Schemes::Oidc.new(issuer: 'https://accounts.google.com')
result = scheme.authenticate(credential, headers: {})

# The result contains the updated headers
puts result[:headers]['Authorization']  # => "Bearer access-token-from-oidc-provider"
```

### `exchange_token`

Exchanges an authorization code for OIDC tokens (access token, ID token, and optional refresh token).

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential containing client information
- `params` (Hash, optional): Additional parameters for the token exchange
  - `code` (String, required): The authorization code from the OIDC provider
  - `redirect_uri` (String, optional): The redirect URI used in the authorization request
  - `code_verifier` (String, optional): The code verifier for PKCE

**Returns:**
- Adk::Auth::ExchangedCredential: The exchanged tokens

**Examples:**

```ruby
# Create OIDC credential
credential = Adk::Auth::Credential.new(
  auth_type: :oidc,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# Exchange authorization code for tokens
scheme = Adk::Auth::Schemes::Oidc.new(
  issuer: 'https://accounts.google.com',
  redirect_uri: 'http://localhost:3000/auth/callback'
)
token = scheme.exchange_token(credential, code: 'authorization-code-from-callback')

# The token contains OIDC tokens
puts token[:access_token]  # => "access-token"
puts token[:id_token]      # => "id-token-jwt"
puts token[:refresh_token] # => "refresh-token" (if granted)
```

### `refresh_token`

Refreshes an expired OIDC access token using the refresh token.

**Parameters:**
- `credential` (Adk::Auth::Credential): The original credential
- `token` (Adk::Auth::ExchangedCredential): The token to refresh

**Returns:**
- Adk::Auth::ExchangedCredential: The refreshed token

**Examples:**

```ruby
# Create a credential
credential = Adk::Auth::Credential.new(
  auth_type: :oidc,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# Assume we have a token with a refresh token
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :oidc,
  access_token: 'expired-access-token',
  refresh_token: 'valid-refresh-token',
  expires_at: Time.now - 60  # Expired 60 seconds ago
)

# Refresh the token
scheme = Adk::Auth::Schemes::Oidc.new(issuer: 'https://accounts.google.com')
refreshed_token = scheme.refresh_token(credential, token)

# The refreshed token has a new access token
puts refreshed_token[:access_token]  # => "new-access-token"
```

### `verify_id_token`

Verifies the ID token from the OIDC provider.

**Parameters:**
- `id_token` (String): The ID token to verify
- `params` (Hash, optional): Additional parameters for verification
  - `nonce` (String, optional): The nonce used in the authorization request
  - `max_age` (Integer, optional): Maximum allowed age of the ID token in seconds

**Returns:**
- Hash: The decoded and verified ID token claims

**Raises:**
- `Adk::Auth::AuthenticationError`: If the ID token is invalid

**Examples:**

```ruby
# Verify an ID token
scheme = Adk::Auth::Schemes::Oidc.new(
  issuer: 'https://accounts.google.com',
  client_id: 'my-client-id'
)

begin
  # Verify with nonce for extra security
  claims = scheme.verify_id_token(id_token, nonce: 'original-nonce-value')
  
  # Use the verified claims
  puts "Authenticated user: #{claims['sub']}"
  puts "Email: #{claims['email']}"
  puts "Name: #{claims['name']}"
rescue Adk::Auth::AuthenticationError => e
  puts "ID token verification failed: #{e.message}"
end
```

## Usage Examples

### Complete OIDC Authorization Flow

```ruby
require 'securerandom'

# Step 1: Create the OIDC scheme
scheme = Adk::Auth::Schemes::Oidc.new(
  issuer: 'https://accounts.google.com',
  redirect_uri: 'http://localhost:3000/auth/callback',
  scopes: ['openid', 'email', 'profile']
)

# Step 2: Set up credential with client details
credential = Adk::Auth::Credential.new(
  auth_type: :oidc,
  client_id: ENV['OIDC_CLIENT_ID'],
  client_secret: ENV['OIDC_CLIENT_SECRET']
)

# Step 3: Generate state and nonce for security
state = SecureRandom.hex(16)
nonce = SecureRandom.hex(16)

# Store these securely in session
session[:oidc_state] = state
session[:oidc_nonce] = nonce

# Step 4: Generate authorization URL and redirect user
auth_url = scheme.authorize_url(credential, state: state, nonce: nonce)
redirect_to auth_url

# Step 5: Handle the callback (in a separate route handler)
def callback
  # Verify state parameter to protect against CSRF
  if params[:state] != session[:oidc_state]
    return render plain: "Invalid state parameter"
  end
  
  # Exchange code for tokens
  token = scheme.exchange_token(credential, code: params[:code])
  
  # Verify ID token
  id_token = token[:id_token]
  claims = scheme.verify_id_token(id_token, nonce: session[:oidc_nonce])
  
  # Create a user session
  session[:user_id] = claims['sub']
  session[:user_email] = claims['email']
  session[:user_name] = claims['name']
  
  # Store tokens for future API calls
  token_store = Adk::Auth::TokenStore.new(session)
  token_store.put('oidc_token', token)
  
  redirect_to '/dashboard'
end
```

### Using with Token Manager

```ruby
# Create OIDC scheme and credential
scheme = Adk::Auth::Schemes::Oidc.new(
  issuer: 'https://login.microsoftonline.com/tenant-id/v2.0',
  redirect_uri: 'http://localhost:3000/auth/callback'
)

credential = Adk::Auth::Credential.new(
  auth_type: :oidc,
  client_id: 'ENV:OIDC_CLIENT_ID',
  client_secret: 'ENV:OIDC_CLIENT_SECRET'
)

# Use with token manager for automatic token management
token_store = Adk::Auth::TokenStore.new(session)
token_manager = Adk::Auth::TokenManager.new(token_store)

# For an interactive app, get or create a token
token_key = 'oidc_token'
if token_manager.has_token?(token_key)
  # Use existing token
  token = token_manager.get_token(token_key)
else
  # Need to start an authentication flow
  auth_url = scheme.authorize_url(credential)
  # (redirect user to auth_url, and process in callback)
end
```

### Making Authenticated API Calls

```ruby
# Assuming we have a valid token from a previous authentication flow
token_store = Adk::Auth::TokenStore.new(session)
token = token_store.get('oidc_token')

# Create HTTP client
require 'net/http'
uri = URI('https://api.example.com/protected-resource')
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

# Create request
request = Net::HTTP::Get.new(uri)

# Authenticate the request
scheme = Adk::Auth::Schemes::Oidc.new
authenticated = scheme.authenticate(token, headers: {})

# Add authentication header to request
request['Authorization'] = authenticated[:headers]['Authorization']

# Make the request
response = http.request(request)
```

## OIDC Provider-Specific Configurations

### Google

```ruby
scheme = Adk::Auth::Schemes::Oidc.new(
  issuer: 'https://accounts.google.com',
  client_id: 'ENV:GOOGLE_CLIENT_ID',
  client_secret: 'ENV:GOOGLE_CLIENT_SECRET',
  redirect_uri: 'http://localhost:3000/auth/google/callback',
  scopes: ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/calendar']
)
```

### Microsoft Azure AD

```ruby
scheme = Adk::Auth::Schemes::Oidc.new(
  issuer: 'https://login.microsoftonline.com/tenant-id/v2.0',
  client_id: 'ENV:AZURE_CLIENT_ID',
  client_secret: 'ENV:AZURE_CLIENT_SECRET',
  redirect_uri: 'http://localhost:3000/auth/azure/callback',
  scopes: ['openid', 'email', 'profile', 'offline_access', 'https://graph.microsoft.com/User.Read']
)
```

### Auth0

```ruby
scheme = Adk::Auth::Schemes::Oidc.new(
  issuer: 'https://your-tenant.auth0.com',
  client_id: 'ENV:AUTH0_CLIENT_ID',
  client_secret: 'ENV:AUTH0_CLIENT_SECRET',
  redirect_uri: 'http://localhost:3000/auth/auth0/callback',
  scopes: ['openid', 'email', 'profile', 'offline_access']
)
```

## Security Considerations

- Store tokens securely, preferably encrypted at rest
- Always validate the ID token's signature and claims
- Use state parameters to prevent CSRF attacks
- Use nonce parameters to prevent replay attacks
- Implement proper token lifecycle management, including expiration and revocation
- Consider using Proof Key for Code Exchange (PKCE) for additional security
- Always use HTTPS for all OIDC-related communications

## See Also

- [Adk::Auth::Credential](../credential.md)
- [Adk::Auth::ExchangedCredential](../exchanged_credential.md)
- [Adk::Auth::Scheme](../scheme.md)
- [Adk::Auth::TokenManager](../token_manager.md)
- [OpenID Connect Troubleshooting](../../troubleshooting/oidc_issues.md) 