# Legate::Auth::Schemes::OAuth2

The `OAuth2` class implements the OAuth 2.0 authentication scheme, which is a widely adopted industry-standard protocol for authorization. This scheme handles the complex token exchange flows between your application, users, and OAuth 2.0 providers.

## Overview

OAuth 2.0 is an authorization framework that enables third-party applications to obtain limited access to a user's account on an HTTP service. It works by delegating user authentication to the service that hosts the user's account and authorizing third-party applications to access that account.

## Class Methods

### `new`

Creates a new OAuth 2.0 authentication scheme.

**Parameters:**
- `authorization_url` (String, optional keyword): The authorization endpoint URL
- `token_url` (String, optional keyword): The token endpoint URL
- `scopes` (Array<String>, optional keyword): The OAuth scopes to request
- `use_pkce` (Boolean, optional keyword): Whether to use PKCE (default: true)
- `additional_params` (Hash, optional keyword): Additional parameters for the authorization request
- `revocation_url` (String, optional keyword): The token revocation endpoint URL
- `**kwargs` (Hash): Additional parameters for the authentication scheme

**Examples:**

```ruby
# Create a basic OAuth2 scheme for authorization code flow
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://provider.com/oauth2/authorize',
  token_url: 'https://provider.com/oauth2/token',
  scopes: ['profile', 'email']
)

# Create an OAuth2 scheme with PKCE disabled
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://provider.com/oauth2/authorize',
  token_url: 'https://provider.com/oauth2/token',
  use_pkce: false
)

# Create an OAuth2 scheme for client credentials
scheme = Legate::Auth::Schemes::OAuth2.new(
  token_url: 'https://provider.com/oauth2/token'
)
```

## Instance Methods

### `scheme_type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:oauth2`

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::OAuth2.new
scheme.scheme_type  # => :oauth2
```

### `validate!`

Validates the scheme configuration. Raises an error if required fields (like `token_url`) are missing.

**Raises:**
- `Legate::Auth::SchemeValidationError`: If the scheme configuration is invalid (e.g. missing `authorization_url` or `token_url`)

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://provider.com/oauth2/authorize',
  token_url: 'https://provider.com/oauth2/token'
)
scheme.validate!  # Passes validation
```

### `build_authorization_uri`

Builds the authorization URL for the OAuth 2.0 flow.

**Parameters:**
- `config` (Legate::Auth::Config): The authentication configuration
- `redirect_uri` (String, optional): The redirect URI for the callback
- `state` (String, optional): The state parameter for CSRF protection

**Returns:**
- String: The authorization URL for the OAuth 2.0 flow

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://provider.com/oauth2/authorize',
  token_url: 'https://provider.com/oauth2/token',
  scopes: ['profile', 'email']
)

config = Legate::Auth::Config.new(scheme: scheme, credential: credential)
auth_url = scheme.build_authorization_uri(
  config,
  'http://localhost:3000/oauth2/callback',
  SecureRandom.hex(16)
)
```

### `apply_to_request`

Applies OAuth 2.0 authentication to a request by adding the access token to the Authorization header.

**Parameters:**
- `request` (Hash): The request to authenticate
- `credential` (Legate::Auth::ExchangedCredential): The exchanged credential containing the access token

**Returns:**
- Hash: The authenticated request with access token in the Authorization header

**Examples:**

```ruby
# Apply authentication to a request
request = { headers: {} }
authenticated = scheme.apply_to_request(request, exchanged_credential)
puts authenticated[:headers]['Authorization']  # => "Bearer access-token"
```

### `exchange_token`

Exchanges an authorization code or config for access and refresh tokens.

**Parameters:**
- `config` (Legate::Auth::Config): The authentication configuration (with response_uri set)
- `credential` (Legate::Auth::Credential): The credential containing client information

**Returns:**
- Legate::Auth::ExchangedCredential: The exchanged tokens

**Examples:**

```ruby
# Exchange authorization code for tokens
token = scheme.exchange_token(config, credential)

puts token[:access_token]   # => "access-token"
puts token[:refresh_token]  # => "refresh-token" (if granted)
puts token[:expires_in]     # => 3600 (seconds until expiration)
```

### `refresh_token`

Refreshes an expired OAuth 2.0 access token using the refresh token.

**Parameters:**
- `exchanged_credential` (Legate::Auth::ExchangedCredential): The token to refresh
- `credential` (Legate::Auth::Credential): The original credential

**Returns:**
- Legate::Auth::ExchangedCredential: The refreshed token

**Examples:**

```ruby
refreshed_token = scheme.refresh_token(expired_token, credential)
puts refreshed_token[:access_token]  # => "new-access-token"
```

### `client_credentials_token`

Obtains a token using the client credentials grant type.

**Parameters:**
- `credential` (Legate::Auth::Credential): The credential containing client_id and client_secret

**Returns:**
- Legate::Auth::ExchangedCredential: The token

**Examples:**

```ruby
token = scheme.client_credentials_token(credential)
```

### `password_token`

Obtains a token using the resource owner password credentials grant type.

**Parameters:**
- `credential` (Legate::Auth::Credential): The credential containing client information
- `username` (String): The resource owner's username
- `password` (String): The resource owner's password

**Returns:**
- Legate::Auth::ExchangedCredential: The token

**Examples:**

```ruby
token = scheme.password_token(credential, 'user@example.com', 'password')
```

### `to_h`

Converts the scheme to a hash representation.

**Returns:**
- Hash: A hash representation of the scheme configuration

## Usage Examples

### Authorization Code Flow

```ruby
require 'securerandom'

# Step 1: Create the OAuth2 scheme
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://provider.com/oauth2/authorize',
  token_url: 'https://provider.com/oauth2/token',
  scopes: ['profile', 'email']
)

# Step 2: Set up credential with client details
credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['OAUTH_CLIENT_ID'],
  client_secret: ENV['OAUTH_CLIENT_SECRET']
)

# Step 3: Create config and build authorization URI
config = Legate::Auth::Config.new(scheme: scheme, credential: credential)
state = SecureRandom.hex(16)
auth_url = config.build_authorization_uri(
  'http://localhost:3000/oauth2/callback',
  state
)

# Step 4: Redirect user to auth_url
# redirect_to auth_url

# Step 5: Handle the callback
config.response_uri = "http://localhost:3000/oauth2/callback?code=12345&state=#{state}"
token = scheme.exchange_token(config, credential)

# Step 6: Store tokens for future API calls
token_store = Legate::Auth::TokenStore.new(session_service)
token_store.store('oauth2_token', token)
```

### Client Credentials Flow

```ruby
# Create an OAuth2 scheme for client credentials
scheme = Legate::Auth::Schemes::OAuth2.new(
  token_url: 'https://provider.com/oauth2/token',
  scopes: ['api:read', 'api:write']
)

# Create a credential with client details
credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['API_CLIENT_ID'],
  client_secret: ENV['API_CLIENT_SECRET']
)

# Get token via client credentials (no user interaction required)
token = scheme.client_credentials_token(credential)
```

### Using with Token Manager

```ruby
# Create OAuth2 scheme and credential
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://provider.com/oauth2/authorize',
  token_url: 'https://provider.com/oauth2/token'
)

credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'ENV:OAUTH_CLIENT_ID',
  client_secret: 'ENV:OAUTH_CLIENT_SECRET'
)

# Use with token manager for automatic token management
token_store = Legate::Auth::TokenStore.new(session_service)
token_manager = Legate::Auth::TokenManager.new(token_store)

# Get a token (will auto-refresh if expired)
token = token_manager.get_token(scheme, credential)
```

## Provider-Specific Configurations

### Google

```ruby
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://accounts.google.com/o/oauth2/auth',
  token_url: 'https://oauth2.googleapis.com/token',
  scopes: ['profile', 'email', 'https://www.googleapis.com/auth/calendar']
)
```

### Microsoft Azure

```ruby
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
  token_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
  scopes: ['User.Read', 'Calendars.Read']
)
```

### GitHub

```ruby
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://github.com/login/oauth/authorize',
  token_url: 'https://github.com/login/oauth/access_token',
  scopes: ['user', 'repo']
)
```

## Security Considerations

- Always use HTTPS for all OAuth 2.0 communications
- Store client secrets securely and never expose them in client-side code
- Implement state parameter validation to prevent CSRF attacks
- Use PKCE extension for public clients to prevent authorization code interception
- Store tokens securely; for at-rest encryption use the opt-in [`Legate::Auth::Encryption`](../encryption) module (TokenStore does not encrypt)
- Implement proper token lifecycle management, including expiration and revocation
- Request only the scopes that your application needs (principle of least privilege)

> **SSRF protection:** When the scheme makes HTTP calls (e.g. to the token endpoint), the token URL is validated by `Legate::Auth::UrlGuard`, which blocks loopback, link-local, private, CGNAT (100.64.0.0/10), and `0.0.0.0/8` addresses. Set `LEGATE_ALLOW_PRIVATE_AUTH_URLS=1` to bypass this in development.

## See Also

- [Legate::Auth::Credential](../credential)
- [Legate::Auth::ExchangedCredential](../exchanged_credential)
- [Legate::Auth::Scheme](../scheme)
- [Legate::Auth::TokenManager](../token_manager)
