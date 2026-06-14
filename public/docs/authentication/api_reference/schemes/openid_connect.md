# Legate::Auth::Schemes::OpenIDConnect

The `OpenIDConnect` class implements the OpenID Connect (OIDC) authentication scheme, which provides a layer of identity verification on top of OAuth 2.0 protocols. It extends the `OAuth2` scheme class. It is also available via the `OIDC` alias.

## Overview

OpenID Connect is a simple identity layer built on top of the OAuth 2.0 protocol. It allows clients to verify the identity of end-users based on the authentication performed by an authorization server, as well as to obtain basic profile information about the end-user in an interoperable and REST-like manner.

## Class Methods

### `new`

Creates a new OpenID Connect authentication scheme.

**Parameters:**
- Inherits all parameters from `OAuth2.new` (authorization_url, token_url, scopes, use_pkce, etc.)
- `discovery_url` (String, optional keyword): The OIDC discovery endpoint URL
- `jwks_url` (String, optional keyword): The JSON Web Key Set URI for token validation
- `userinfo_url` (String, optional keyword): The userinfo endpoint URL
- `issuer` (String, optional keyword): The OIDC issuer URL
- `provider_uri` (String, optional keyword): The provider URI
- `client_id` (String, optional keyword): The client ID for the OIDC provider
- `**kwargs` (Hash): Additional parameters for the authentication scheme

**Examples:**

```ruby
# Create a basic OIDC scheme with discovery
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
  scopes: ['openid', 'email', 'profile']
)

# With explicit endpoint configuration
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  authorization_url: 'https://login.microsoftonline.com/tenant-id/oauth2/v2.0/authorize',
  token_url: 'https://login.microsoftonline.com/tenant-id/oauth2/v2.0/token',
  userinfo_url: 'https://graph.microsoft.com/oidc/userinfo',
  jwks_url: 'https://login.microsoftonline.com/tenant-id/discovery/v2.0/keys',
  scopes: ['openid', 'email', 'profile', 'offline_access']
)
```

## Instance Methods

### `scheme_type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:openid_connect`

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::OpenIDConnect.new
scheme.scheme_type  # => :openid_connect
```

### `validate!`

Validates the scheme configuration.

**Raises:**
- `Legate::Auth::SchemeValidationError`: If the scheme configuration is invalid (e.g. missing `authorization_url` or `token_url`)

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
  token_url: 'https://oauth2.googleapis.com/token'
)
scheme.validate!
```

### `build_authorization_uri`

Builds the authorization URL for the OpenID Connect flow. Includes OIDC-specific parameters like nonce.

**Parameters:**
- `config` (Legate::Auth::Config): The authentication configuration
- `redirect_uri` (String, optional): The redirect URI for the callback
- `state` (String, optional): The state parameter for CSRF protection

**Returns:**
- String: The authorization URL for the OIDC flow

**Examples:**

```ruby
config = Legate::Auth::Config.new(scheme: scheme, credential: credential)
auth_url = scheme.build_authorization_uri(
  config,
  'http://localhost:3000/auth/callback',
  SecureRandom.hex(16)
)
```

### `apply_to_request`

Applies OIDC authentication to a request (inherited from OAuth2).

**Parameters:**
- `request` (Hash): The request to authenticate
- `credential` (Legate::Auth::ExchangedCredential): The exchanged credential

**Returns:**
- Hash: The authenticated request with access token in the Authorization header

### `exchange_token`

Exchanges an authorization code for OIDC tokens (access token, ID token, and optional refresh token).

**Parameters:**
- `config` (Legate::Auth::Config): The authentication configuration
- `credential` (Legate::Auth::Credential): The credential containing client information

**Returns:**
- Legate::Auth::ExchangedCredential: The exchanged tokens

**Examples:**

```ruby
token = scheme.exchange_token(config, credential)

puts token[:access_token]  # => "access-token"
puts token[:id_token]      # => "id-token-jwt"
puts token[:refresh_token] # => "refresh-token" (if granted)
```

### `discover_endpoints`

Discovers OIDC endpoints from the discovery URL.

**Returns:**
- Hash: The discovered endpoint configuration

### `get_userinfo`

Retrieves user information from the OIDC userinfo endpoint.

**Parameters:**
- `access_token` (String): The access token to use for the userinfo request

**Returns:**
- Hash: The user information retrieved from the userinfo endpoint

**Examples:**

```ruby
user_info = scheme.get_userinfo(token[:access_token])

puts "User ID: #{user_info['sub']}"
puts "Email: #{user_info['email']}"
puts "Name: #{user_info['name']}"
```

### `verify_id_token`

Verifies the ID token from the OIDC provider.

**Parameters:**
- `id_token` (String): The ID token to verify
- `nonce` (String, optional): The nonce used in the authorization request
- `audience` (String, optional): The expected audience for the token

**Returns:**
- Hash: The decoded and verified ID token claims

**Raises:**
- `Legate::Auth::TokenVerificationError`: If the ID token is invalid (signature, claim, or nonce mismatch)

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
  client_id: 'my-client-id'
)

begin
  claims = scheme.verify_id_token(id_token, 'original-nonce-value')
  puts "Authenticated user: #{claims['sub']}"
  puts "Email: #{claims['email']}"
rescue Legate::Auth::TokenVerificationError => e
  puts "ID token verification failed: #{e.message}"
end
```

### `to_h`

Converts the scheme to a hash representation.

**Returns:**
- Hash: A hash representation of the scheme configuration

## Usage Examples

### Complete OIDC Authorization Flow

```ruby
require 'securerandom'

# Step 1: Create the OIDC scheme
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
  scopes: ['openid', 'email', 'profile']
)

# Step 2: Set up credential with client details
credential = Legate::Auth::Credential.new(
  auth_type: :oidc,
  client_id: ENV['OIDC_CLIENT_ID'],
  client_secret: ENV['OIDC_CLIENT_SECRET']
)

# Step 3: Create config and build authorization URI
config = Legate::Auth::Config.new(scheme: scheme, credential: credential)
state = SecureRandom.hex(16)
auth_url = config.build_authorization_uri(
  'http://localhost:3000/auth/callback',
  state
)

# Step 4: Redirect user to auth_url
# redirect_to auth_url

# Step 5: Handle the callback
config.response_uri = "http://localhost:3000/auth/callback?code=12345&state=#{state}"
token = scheme.exchange_token(config, credential)

# Step 6: Verify ID token
claims = scheme.verify_id_token(token[:id_token])

# Step 7: Get user info
user_info = scheme.get_userinfo(token[:access_token])

# Step 8: Create user session
session[:user_id] = claims['sub']
session[:user_email] = claims['email']
```

### Using with Token Manager

```ruby
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration'
)

credential = Legate::Auth::Credential.new(
  auth_type: :oidc,
  client_id: 'ENV:OIDC_CLIENT_ID',
  client_secret: 'ENV:OIDC_CLIENT_SECRET'
)

token_store = Legate::Auth::TokenStore.new(session_service)
token_manager = Legate::Auth::TokenManager.new(token_store)

# Get a token (will auto-refresh if expired)
token = token_manager.get_token(scheme, credential)
```

## Provider-Specific Configurations

### Google

```ruby
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
  scopes: ['openid', 'email', 'profile']
)
```

### Microsoft Azure AD / Entra ID

```ruby
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  authorization_url: 'https://login.microsoftonline.com/tenant-id/oauth2/v2.0/authorize',
  token_url: 'https://login.microsoftonline.com/tenant-id/oauth2/v2.0/token',
  userinfo_url: 'https://graph.microsoft.com/oidc/userinfo',
  scopes: ['openid', 'email', 'profile', 'offline_access']
)
```

### Auth0

```ruby
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://your-tenant.auth0.com/.well-known/openid-configuration',
  scopes: ['openid', 'email', 'profile', 'offline_access']
)
```

## Security Considerations

- Store tokens securely; for at-rest encryption use the opt-in [`Legate::Auth::Encryption`](../encryption) module (TokenStore does not encrypt)
- Always validate the ID token's signature and claims
- Use state parameters to prevent CSRF attacks
- Use nonce parameters to prevent replay attacks
- Implement proper token lifecycle management, including expiration
- Consider using PKCE for additional security
- Always use HTTPS for all OIDC-related communications

## See Also

- [Legate::Auth::Schemes::OAuth2](./oauth2)
- [Legate::Auth::Credential](../credential)
- [Legate::Auth::ExchangedCredential](../exchanged_credential)
- [Legate::Auth::Scheme](../scheme)
- [Legate::Auth::TokenManager](../token_manager)
