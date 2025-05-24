# Adk::Auth::Schemes::OpenIdConnect

The `OpenIdConnect` class is an enhanced implementation of the OpenID Connect (OIDC) authentication protocol that extends the base Oidc class with additional features and optimizations. It provides a comprehensive identity layer on top of OAuth 2.0, focusing on secure identity verification and user information exchange.

## Overview

OpenID Connect builds upon OAuth 2.0 to add a standardized identity layer that enables clients to verify user identities and obtain basic profile information. This implementation supports the full OIDC protocol including ID tokens, userinfo endpoints, and various authentication flows.

## Class Methods

### `new`

Creates a new OpenID Connect authentication scheme with enhanced features.

**Parameters:**
- `issuer` (String, optional): The OIDC issuer URL
- `client_id` (String, optional): The client ID for the OIDC provider
- `client_secret` (String, optional): The client secret for the OIDC provider
- `redirect_uri` (String, optional): The redirect URI for the OIDC flow
- `scopes` (Array<String>, optional): The OIDC scopes to request (default: ['openid', 'email', 'profile'])
- `discovery` (Boolean, optional): Whether to use OIDC discovery (default: true)
- `userinfo_endpoint` (String, optional): The userinfo endpoint URL
- `jwks_uri` (String, optional): The JSON Web Key Set URI for token validation
- `token_endpoint_auth_method` (String, optional): The token endpoint authentication method
- `kwargs` (Hash, optional): Additional parameters for the authentication scheme

**Examples:**

```ruby
# Create a basic OpenID Connect scheme with discovery
scheme = Adk::Auth::Schemes::OpenIdConnect.new(
  issuer: 'https://accounts.google.com',
  client_id: 'ENV:OIDC_CLIENT_ID',
  client_secret: 'ENV:OIDC_CLIENT_SECRET',
  redirect_uri: 'http://localhost:3000/auth/callback'
)

# With manual configuration (no discovery)
scheme = Adk::Auth::Schemes::OpenIdConnect.new(
  client_id: 'ENV:OIDC_CLIENT_ID',
  client_secret: 'ENV:OIDC_CLIENT_SECRET',
  redirect_uri: 'http://localhost:3000/auth/callback',
  discovery: false,
  authorize_url: 'https://login.microsoftonline.com/tenant-id/oauth2/v2.0/authorize',
  token_url: 'https://login.microsoftonline.com/tenant-id/oauth2/v2.0/token',
  userinfo_endpoint: 'https://graph.microsoft.com/oidc/userinfo',
  jwks_uri: 'https://login.microsoftonline.com/tenant-id/discovery/v2.0/keys'
)
```

## Instance Methods

### `type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:openid_connect`

**Examples:**

```ruby
scheme = Adk::Auth::Schemes::OpenIdConnect.new(issuer: 'https://accounts.google.com')
scheme.type  # => :openid_connect
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
# Create a valid OpenID Connect credential
credential = Adk::Auth::Credential.new(
  auth_type: :openid_connect,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# Validate the credential
scheme = Adk::Auth::Schemes::OpenIdConnect.new(issuer: 'https://accounts.google.com')
scheme.validate_credential(credential)  # => true
```

### `authorize_url`

Generates the authorization URL for the OpenID Connect flow.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential containing client information
- `params` (Hash, optional): Additional parameters for the authorization URL
  - `state` (String, optional): State parameter for CSRF protection
  - `nonce` (String, optional): Nonce parameter for replay protection
  - `prompt` (String, optional): Prompt parameter for the authorization request
  - `login_hint` (String, optional): Hint about the login identifier
  - `max_age` (Integer, optional): Maximum authentication age
  - `ui_locales` (String, optional): UI locales preference
  - `acr_values` (String, optional): Authentication Context Class Reference values

**Returns:**
- String: The authorization URL for the OpenID Connect flow

**Examples:**

```ruby
# Create OpenID Connect credential
credential = Adk::Auth::Credential.new(
  auth_type: :openid_connect,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# Generate an authorization URL with additional parameters
scheme = Adk::Auth::Schemes::OpenIdConnect.new(
  issuer: 'https://accounts.google.com',
  redirect_uri: 'http://localhost:3000/auth/callback'
)
auth_url = scheme.authorize_url(
  credential, 
  state: SecureRandom.hex(16),
  nonce: SecureRandom.hex(16),
  prompt: 'login',  # Force login screen
  login_hint: 'user@example.com'  # Pre-fill email
)

# Redirect the user to this URL
puts "Please visit: #{auth_url}"
```

### `authenticate`

Authenticates a request using the OpenID Connect access token.

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
  auth_type: :openid_connect,
  access_token: 'access-token-from-oidc-provider'
)

# Authenticate a request
scheme = Adk::Auth::Schemes::OpenIdConnect.new(issuer: 'https://accounts.google.com')
result = scheme.authenticate(credential, headers: {})

# The result contains the updated headers
puts result[:headers]['Authorization']  # => "Bearer access-token-from-oidc-provider"
```

### `exchange_token`

Exchanges an authorization code for OpenID Connect tokens.

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
# Create OpenID Connect credential
credential = Adk::Auth::Credential.new(
  auth_type: :openid_connect,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# Exchange authorization code for tokens
scheme = Adk::Auth::Schemes::OpenIdConnect.new(
  issuer: 'https://accounts.google.com',
  redirect_uri: 'http://localhost:3000/auth/callback'
)
token = scheme.exchange_token(credential, code: 'authorization-code-from-callback')

# The token contains OpenID Connect tokens
puts token[:access_token]  # => "access-token"
puts token[:id_token]      # => "id-token-jwt"
puts token[:refresh_token] # => "refresh-token" (if granted)
```

### `refresh_token`

Refreshes an expired OpenID Connect access token using the refresh token.

**Parameters:**
- `credential` (Adk::Auth::Credential): The original credential
- `token` (Adk::Auth::ExchangedCredential): The token to refresh

**Returns:**
- Adk::Auth::ExchangedCredential: The refreshed token

**Examples:**

```ruby
# Create a credential
credential = Adk::Auth::Credential.new(
  auth_type: :openid_connect,
  client_id: 'my-client-id',
  client_secret: 'my-client-secret'
)

# Assume we have a token with a refresh token
token = Adk::Auth::ExchangedCredential.new(
  auth_type: :openid_connect,
  access_token: 'expired-access-token',
  refresh_token: 'valid-refresh-token',
  id_token: 'id-token',
  expires_at: Time.now - 60  # Expired 60 seconds ago
)

# Refresh the token
scheme = Adk::Auth::Schemes::OpenIdConnect.new(issuer: 'https://accounts.google.com')
refreshed_token = scheme.refresh_token(credential, token)

# The refreshed token has a new access token
puts refreshed_token[:access_token]  # => "new-access-token"
```

### `verify_id_token`

Verifies the ID token from the OpenID Connect provider with comprehensive validation.

**Parameters:**
- `id_token` (String): The ID token to verify
- `params` (Hash, optional): Additional parameters for verification
  - `nonce` (String, optional): The nonce used in the authorization request
  - `max_age` (Integer, optional): Maximum allowed age of the ID token in seconds
  - `acr_values` (String, Array<String>, optional): Required Authentication Context Class References

**Returns:**
- Hash: The decoded and verified ID token claims

**Raises:**
- `Adk::Auth::AuthenticationError`: If the ID token is invalid

**Examples:**

```ruby
# Verify an ID token with comprehensive validation
scheme = Adk::Auth::Schemes::OpenIdConnect.new(
  issuer: 'https://accounts.google.com',
  client_id: 'my-client-id'
)

begin
  # Verify with strict parameters
  claims = scheme.verify_id_token(
    id_token,
    nonce: 'original-nonce-value',
    max_age: 300,  # 5 minutes
    acr_values: ['phr', 'phrh']  # Required authentication levels
  )
  
  # Use the verified claims
  puts "Authenticated user: #{claims['sub']}"
  puts "Email: #{claims['email']}"
  puts "Name: #{claims['name']}"
rescue Adk::Auth::AuthenticationError => e
  puts "ID token verification failed: #{e.message}"
end
```

### `userinfo`

Retrieves user information from the OpenID Connect userinfo endpoint.

**Parameters:**
- `access_token` (String): The access token to use for the userinfo request
- `params` (Hash, optional): Additional parameters for the userinfo request

**Returns:**
- Hash: The user information retrieved from the userinfo endpoint

**Examples:**

```ruby
# Get a token with access_token
token = scheme.exchange_token(credential, code: 'authorization-code')

# Get user information
user_info = scheme.userinfo(token[:access_token])

# Use the user information
puts "User ID: #{user_info['sub']}"
puts "Email: #{user_info['email']}"
puts "Name: #{user_info['name']}"
```

## Usage Examples

### Complete OpenID Connect Flow with User Profile

```ruby
require 'securerandom'

# Step 1: Create the OpenID Connect scheme
scheme = Adk::Auth::Schemes::OpenIdConnect.new(
  issuer: 'https://accounts.google.com',
  redirect_uri: 'http://localhost:3000/auth/callback',
  scopes: ['openid', 'email', 'profile']
)

# Step 2: Set up credential with client details
credential = Adk::Auth::Credential.new(
  auth_type: :openid_connect,
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
  id_claims = scheme.verify_id_token(id_token, nonce: session[:oidc_nonce])
  
  # Get additional user information from userinfo endpoint
  user_info = scheme.userinfo(token[:access_token])
  
  # Combine claims from ID token and userinfo
  user_profile = id_claims.merge(user_info)
  
  # Create a user session
  session[:user_id] = user_profile['sub']
  session[:user_email] = user_profile['email']
  session[:user_name] = user_profile['name']
  session[:user_picture] = user_profile['picture']
  
  # Store tokens for future API calls
  token_store = Adk::Auth::TokenStore.new(session)
  token_store.put('oidc_token', token)
  
  redirect_to '/dashboard'
end
```

### OpenID Connect with PKCE for Enhanced Security

```ruby
require 'securerandom'
require 'base64'
require 'digest'

# Generate PKCE code verifier and challenge
code_verifier = SecureRandom.urlsafe_base64(64)
code_challenge = Base64.urlsafe_encode64(
  Digest::SHA256.digest(code_verifier),
  padding: false
)

# Store code verifier for later use
session[:code_verifier] = code_verifier

# Create the OpenID Connect scheme
scheme = Adk::Auth::Schemes::OpenIdConnect.new(
  issuer: 'https://login.microsoftonline.com/tenant-id/v2.0',
  redirect_uri: 'http://localhost:3000/auth/callback'
)

# Set up credential
credential = Adk::Auth::Credential.new(
  auth_type: :openid_connect,
  client_id: 'ENV:OIDC_CLIENT_ID',
  client_secret: 'ENV:OIDC_CLIENT_SECRET'
)

# Generate state and nonce
state = SecureRandom.hex(16)
nonce = SecureRandom.hex(16)

# Store security parameters
session[:oidc_state] = state
session[:oidc_nonce] = nonce

# Generate authorization URL with PKCE
auth_url = scheme.authorize_url(
  credential,
  state: state,
  nonce: nonce,
  code_challenge: code_challenge,
  code_challenge_method: 'S256'
)

# Redirect user to authorization URL
redirect_to auth_url

# In the callback handler:
def callback
  # Verify state
  if params[:state] != session[:oidc_state]
    return render plain: "Invalid state parameter"
  end
  
  # Exchange code using the stored code_verifier
  token = scheme.exchange_token(
    credential,
    code: params[:code],
    code_verifier: session[:code_verifier]
  )
  
  # Continue with ID token verification and user session creation
  # ...
end
```

### Custom Token Processing with Claims Verification

```ruby
# Create the OpenID Connect scheme
scheme = Adk::Auth::Schemes::OpenIdConnect.new(
  issuer: 'https://auth.example.com',
  scopes: ['openid', 'email', 'profile', 'groups']
)

# Function to process and verify tokens with custom rules
def process_authentication(scheme, token)
  # Verify the ID token
  id_claims = scheme.verify_id_token(token[:id_token])
  
  # Get user info
  user_info = scheme.userinfo(token[:access_token])
  
  # Verify required claims
  required_claims = ['sub', 'email', 'groups']
  missing_claims = required_claims - (id_claims.keys + user_info.keys)
  
  if missing_claims.any?
    raise "Missing required claims: #{missing_claims.join(', ')}"
  end
  
  # Check group membership (authorization)
  groups = user_info['groups'] || []
  
  if !groups.include?('app-users')
    raise "User does not have required group membership"
  end
  
  # Create combined profile
  profile = id_claims.merge(user_info)
  
  # Return processed user profile
  {
    user_id: profile['sub'],
    email: profile['email'],
    name: profile['name'],
    groups: groups,
    roles: derive_roles_from_groups(groups)
  }
end

# Example of role derivation
def derive_roles_from_groups(groups)
  roles = []
  roles << 'admin' if groups.include?('app-admins')
  roles << 'user' if groups.include?('app-users')
  roles << 'api-access' if groups.include?('api-users')
  roles
end
```

## Provider-Specific Configurations

### Google

```ruby
scheme = Adk::Auth::Schemes::OpenIdConnect.new(
  issuer: 'https://accounts.google.com',
  client_id: 'ENV:GOOGLE_CLIENT_ID',
  client_secret: 'ENV:GOOGLE_CLIENT_SECRET',
  redirect_uri: 'http://localhost:3000/auth/google/callback',
  scopes: ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/calendar']
)
```

### Microsoft Azure AD / Entra ID

```ruby
scheme = Adk::Auth::Schemes::OpenIdConnect.new(
  issuer: 'https://login.microsoftonline.com/tenant-id/v2.0',
  client_id: 'ENV:AZURE_CLIENT_ID',
  client_secret: 'ENV:AZURE_CLIENT_SECRET',
  redirect_uri: 'http://localhost:3000/auth/azure/callback',
  scopes: ['openid', 'email', 'profile', 'offline_access', 'https://graph.microsoft.com/User.Read']
)
```

### Auth0

```ruby
scheme = Adk::Auth::Schemes::OpenIdConnect.new(
  issuer: 'https://your-tenant.auth0.com',
  client_id: 'ENV:AUTH0_CLIENT_ID',
  client_secret: 'ENV:AUTH0_CLIENT_SECRET',
  redirect_uri: 'http://localhost:3000/auth/auth0/callback',
  scopes: ['openid', 'email', 'profile', 'offline_access']
)
```

### Okta

```ruby
scheme = Adk::Auth::Schemes::OpenIdConnect.new(
  issuer: 'https://your-org.okta.com',
  client_id: 'ENV:OKTA_CLIENT_ID',
  client_secret: 'ENV:OKTA_CLIENT_SECRET',
  redirect_uri: 'http://localhost:3000/auth/okta/callback',
  scopes: ['openid', 'email', 'profile', 'groups']
)
```

## Security Considerations

- Store tokens securely, preferably encrypted at rest
- Always validate the ID token's signature and claims
- Verify that the ID token audience matches your client ID
- Use state parameters to prevent CSRF attacks
- Use nonce parameters to prevent replay attacks
- Consider using Proof Key for Code Exchange (PKCE) for all clients
- Implement proper token lifecycle management, including expiration
- Use refresh tokens with appropriate expiration policies
- Always use HTTPS for all OIDC-related communications
- Validate claims from ID tokens and userinfo endpoint for consistency

## Advanced Features

### Dynamic Client Registration

```ruby
# Register a new client dynamically
registration_params = {
  application_type: 'web',
  redirect_uris: ['https://app.example.com/callback'],
  client_name: 'My OIDC Client',
  logo_uri: 'https://app.example.com/logo.png',
  subject_type: 'pairwise',
  token_endpoint_auth_method: 'client_secret_basic',
  jwks_uri: 'https://app.example.com/jwks.json',
  userinfo_encrypted_response_alg: 'RSA1_5',
  userinfo_encrypted_response_enc: 'A128CBC-HS256'
}

dynamic_client = scheme.register_client(registration_params)

# Use the registered client details
credential = Adk::Auth::Credential.new(
  auth_type: :openid_connect,
  client_id: dynamic_client['client_id'],
  client_secret: dynamic_client['client_secret']
)
```

### Token Introspection

```ruby
# Introspect a token to check its validity and metadata
introspection_result = scheme.introspect_token(token[:access_token], 'access_token')

if introspection_result['active']
  puts "Token is active"
  puts "Username: #{introspection_result['username']}"
  puts "Scope: #{introspection_result['scope']}"
  puts "Expires at: #{Time.at(introspection_result['exp'])}"
else
  puts "Token is not active"
end
```

## See Also

- [Adk::Auth::Schemes::OpenIDConnect (OIDC)](./oidc.md)
- [Adk::Auth::Credential](../credential.md)
- [Adk::Auth::ExchangedCredential](../exchanged_credential.md)
- [Adk::Auth::Scheme](../scheme.md)
- [Adk::Auth::TokenManager](../token_manager.md)
- [OpenID Connect Troubleshooting](../../troubleshooting/oidc_issues.md) 