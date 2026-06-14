# Legate::Auth::Config

The `Config` class represents the configuration for interactive authentication flows. It includes all the necessary information to initiate, track, and complete an authentication process that requires user interaction.

## Overview

In interactive authentication flows like OAuth2 or OpenID Connect, the user needs to be redirected to an authentication provider to authenticate and grant permissions. The `Config` class encapsulates all the details needed for this interaction, including the scheme, credential, redirect URI, and callback handling.

## Class Methods

### `new`

Creates a new authentication configuration instance.

**Parameters:**
- `scheme` (Legate::Auth::Scheme): The authentication scheme to use
- `credential` (Legate::Auth::Credential): The credential for the authentication flow
- `auth_request_id` (String, optional): A unique identifier for this authentication request (default: nil)
- `options` (Hash, optional): Additional configuration options (default: {})

**Examples:**

```ruby
# Create a basic authentication configuration
config = Legate::Auth::Config.new(
  scheme: oauth2_scheme,
  credential: oauth2_credential
)

# With an explicit request ID and options
config = Legate::Auth::Config.new(
  scheme: oauth2_scheme,
  credential: oauth2_credential,
  auth_request_id: 'req_123456',
  options: { prompt: 'consent' }
)
```

### `from_h`

Creates a Config instance from a hash representation.

**Parameters:**
- `hash` (Hash): The hash to create the config from
- `scheme` (Legate::Auth::Scheme, optional): The scheme to associate (default: nil)
- `credential` (Legate::Auth::Credential, optional): The credential to associate (default: nil)

**Returns:**
- Legate::Auth::Config: A new Config instance

**Examples:**

```ruby
config = Legate::Auth::Config.from_h(
  saved_hash,
  scheme: oauth2_scheme,
  credential: oauth2_credential
)
```

## Instance Attributes

### Readers (read-only)

- `scheme` - The authentication scheme
- `credential` - The authentication credential
- `auth_request_id` - The unique request identifier

### Accessors (read/write)

- `auth_uri` - The URI to redirect the user to for authentication
- `redirect_uri` - The redirect URI for the callback
- `state` - The state parameter for CSRF protection
- `pkce` - PKCE parameters for the flow
- `response_uri` - The response URI from the provider callback
- `options` - Additional configuration options

## Instance Methods

### `build_authorization_uri`

Builds the authorization URI for the authentication flow using the associated scheme.

**Parameters:**
- `redirect_uri` (String, optional): The redirect URI for the callback
- `state` (String, optional): The state parameter for CSRF protection

**Returns:**
- String: The authorization URI

**Examples:**

```ruby
config = Legate::Auth::Config.new(
  scheme: oauth2_scheme,
  credential: oauth2_credential
)

auth_uri = config.build_authorization_uri(
  'https://app.example.com/callback',
  SecureRandom.hex(16)
)
```

### `to_h`

Converts the configuration to a hash.

**Parameters:**
- `include_credentials` (Boolean, optional): Whether to include credential data (default: false)

**Returns:**
- Hash: A hash representation of the configuration

**Examples:**

```ruby
config = Legate::Auth::Config.new(
  scheme: oauth2_scheme,
  credential: oauth2_credential,
  auth_request_id: 'req_123456'
)

# Without credentials (safe for logging)
puts config.to_h

# With credentials included
puts config.to_h(include_credentials: true)
```

### `validate_response!`

Validates an authentication response against this request configuration (matching request ID, presence of a response URI, and state).

**Parameters:**
- `response_config` (Legate::Auth::Config): The response configuration to validate against this request

**Returns:**
- Boolean: `true` if the response is valid

**Raises:**
- `Legate::Auth::ConfigurationError`: If the response is invalid (ID mismatch, missing response URI, or state mismatch)

**Examples:**

```ruby
# Validate a response Config against the original request Config
config.validate_response!(response_config)
```

## Usage in Authentication Flows

The `Config` class is a key component in interactive authentication flows:

1. **Creation**: A `Config` is created with the scheme and credential
2. **URI Generation**: The config builds the authorization URI via `build_authorization_uri`
3. **User Redirection**: The application redirects the user to the `auth_uri`
4. **Callback Handling**: When the user completes authentication, the provider redirects back with an authorization code or token
5. **Request Matching**: The application matches the callback to the original request using the `auth_request_id`

Here's an example of how it's used in a typical OAuth2 flow:

```ruby
# 1. Configure the OAuth2 scheme and credential
scheme = Legate::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['profile', 'email']
)

credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET']
)

# 2. Create a Config and build the authorization URI
config = Legate::Auth::Config.new(
  scheme: scheme,
  credential: credential
)

auth_uri = config.build_authorization_uri(
  'https://app.example.com/callback',
  SecureRandom.hex(16)
)

# 3. In a web application, redirect the user to the auth URI
# redirect_to auth_uri

# 4. When the user is redirected back, set the response URI on the config
config.response_uri = 'https://app.example.com/callback?code=12345&state=abc123'

# 5. Exchange the authorization code for a token
#    (exchange_token reads code/state from config.response_uri and verifies state)
token = scheme.exchange_token(config, credential)
```

## Security Considerations

- The `auth_request_id` should be cryptographically secure to prevent request forgery
- State parameters should be validated on callback to prevent CSRF attacks
- The `auth_uri` should always use HTTPS to protect the authentication process

## See Also

- [Legate::Auth::Scheme](./scheme)
- [Legate::Auth::Schemes::OAuth2](./schemes/oauth2)
- [Legate::Auth::Schemes::OpenIDConnect](./schemes/openid_connect)
- [Legate::Auth::ExchangedCredential](./exchanged_credential)
