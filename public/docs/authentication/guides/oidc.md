# OpenID Connect Authentication

OpenID Connect (OIDC) is an identity layer built on top of OAuth 2.0 that allows clients to verify the identity of end-users. The Legate Ruby library provides comprehensive support for OpenID Connect authentication.

## Overview

OpenID Connect extends OAuth 2.0 with identity verification functionality, allowing applications to:

- Authenticate users with an identity provider
- Obtain basic profile information about the user
- Receive verified identity information via a JWT (JSON Web Token) called an ID token
- Access additional user information via standardized endpoints

## Configuration

### Creating an OpenID Connect Scheme

There are two main ways to configure an OpenID Connect scheme:

#### Using Discovery

The simplest approach is to use OpenID Connect Discovery, which automatically fetches configuration:

```ruby
# Configure using the provider's discovery URL
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration'
)

# Alternatively, specify the provider URI
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  provider_uri: 'https://accounts.google.com'
)
```

#### Manual Configuration

You can also manually specify all the necessary endpoints:

```ruby
# Configure by explicitly providing all endpoints
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  authorization_url: 'https://accounts.google.com/o/oauth2/auth',
  token_url: 'https://oauth2.googleapis.com/token',
  userinfo_url: 'https://openidconnect.googleapis.com/v1/userinfo',
  jwks_url: 'https://www.googleapis.com/oauth2/v3/certs',
  scopes: ['openid', 'profile', 'email']
)
```

### Creating an OpenID Connect Credential

```ruby
# Basic OpenID Connect credential (use :oidc — :openid_connect is not a
# valid credential auth_type and would raise CredentialError)
credential = Legate::Auth::Credential.new(
  auth_type: :oidc,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET']
)

# With additional options
credential = Legate::Auth::Credential.new(
  auth_type: :oidc,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET'],
  additional_params: {
    'prompt' => 'login'  # Force user to re-authenticate
  }
)
```

## Authentication Flow

The OpenID Connect authentication flow is similar to the OAuth 2.0 authorization code flow, with added identity verification:

```ruby
# 1. Configure the OpenID Connect scheme using discovery
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
  scopes: ['openid', 'profile', 'email']
)

# 2. Configure the credential (use :oidc — :openid_connect is not a valid
#    credential auth_type and would raise CredentialError)
credential = Legate::Auth::Credential.new(
  auth_type: :oidc,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET']
)

# 3. Build the authorization URI via a Config and redirect the user
config = Legate::Auth::Config.new(scheme: scheme, credential: credential)
state = SecureRandom.hex(16)
auth_url = config.build_authorization_uri('https://your-app.com/callback', state)
# redirect_to auth_url

# 4. On the callback, set the response URI on the config
config.response_uri = 'https://your-app.com/callback?code=12345&state=abcde'

# 5. Exchange the authorization code for tokens (includes an ID token)
token = scheme.exchange_token(config, credential)
puts token[:access_token]
puts token[:id_token]
```

> This shows the direct `Config`/scheme flow. Tools can also drive OIDC
> interactively via `context.with_authentication` (see
> [`ToolContextExtension`](../api_reference/tool_context_extension)).

## Key OpenID Connect Features

### ID Token

The ID token is a JWT containing verified information about the user:

```ruby
# The token exchange process returns an ID token automatically
# In an ExchangedCredential, you can access it as:
id_token = exchanged_credential[:id_token]

# To decode and verify the token
require 'jwt'
decoded_token = JWT.decode(id_token, nil, false)[0]

# To access claims
user_email = decoded_token['email']
name = decoded_token['name']
```

### UserInfo Endpoint

For more detailed user information, you can call the UserInfo endpoint:

```ruby
# Get an access token
access_token = exchanged_credential[:access_token]

# Create the scheme (or use existing one)
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration'
)

# Fetch user information
user_info = scheme.get_userinfo(access_token)

# Access user data
email = user_info['email']
name = user_info['name']
picture = user_info['picture']
```

## Provider-Specific Configurations

### Google OpenID Connect

```ruby
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
  scopes: ['openid', 'profile', 'email'],
  additional_params: {
    'prompt' => 'consent',
    'access_type' => 'offline'
  }
)
```

### Microsoft Azure OpenID Connect

```ruby
tenant_id = 'common'  # Use 'common' for multi-tenant, or a specific tenant ID

scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: "https://login.microsoftonline.com/#{tenant_id}/v2.0/.well-known/openid-configuration",
  scopes: ['openid', 'profile', 'email', 'offline_access']
)
```

### Auth0

```ruby
domain = 'your-domain.auth0.com'

scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: "https://#{domain}/.well-known/openid-configuration",
  scopes: ['openid', 'profile', 'email']
)
```

## Security Considerations

- **Nonce Verification**: The library automatically adds a nonce parameter to prevent replay attacks
- **ID Token Validation**: Always verify the ID token signature, issuer, audience, and expiration
- **Scopes**: Request only the scopes your application needs
- **Secure Storage**: Tokens are cached in scoped session state as plaintext; for at-rest encryption, apply the opt-in `Legate::Auth::Encryption` module yourself

## Advanced Features

### PKCE (Proof Key for Code Exchange)

```ruby
# PKCE is enabled by default
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
  use_pkce: true  # This is the default
)
```

### Prompt Parameter

Control the authentication experience using the prompt parameter:

```ruby
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
  additional_params: {
    'prompt' => 'login'  # Options: none, login, consent, select_account
  }
)
```

## Troubleshooting

If you encounter issues with OpenID Connect authentication:

- Ensure 'openid' is included in the requested scopes
- Verify that your client is properly registered with the identity provider
- Check that redirect URIs exactly match those registered with the provider
- See the [OpenID Connect Troubleshooting Guide](../troubleshooting/oidc_issues) for detailed solutions

## Related Topics

- [OAuth2 Authentication](./oauth2) - Learn more about the underlying OAuth2 protocol
- [Service Account Authentication](./service_account) - Use service accounts for server-to-server authentication
- [Token Lifecycle Management](./token_lifecycle) - Advanced token management techniques

## Next Steps

- [OAuth2 Authentication](./oauth2): Learn more about the underlying OAuth2 protocol
- [Service Account Authentication](./service_account): Use service accounts for server-to-server authentication
- [Token Lifecycle Management](./token_lifecycle): Advanced token management techniques 