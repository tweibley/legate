# OpenID Connect Authentication

OpenID Connect (OIDC) is an identity layer built on top of OAuth 2.0 that allows clients to verify the identity of end-users. The ADK Ruby library provides comprehensive support for OpenID Connect authentication.

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
scheme = Adk::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration'
)

# Alternatively, specify the provider URI
scheme = Adk::Auth::Schemes::OpenIDConnect.new(
  provider_uri: 'https://accounts.google.com'
)
```

#### Manual Configuration

You can also manually specify all the necessary endpoints:

```ruby
# Configure by explicitly providing all endpoints
scheme = Adk::Auth::Schemes::OpenIDConnect.new(
  authorization_url: 'https://accounts.google.com/o/oauth2/auth',
  token_url: 'https://oauth2.googleapis.com/token',
  userinfo_url: 'https://openidconnect.googleapis.com/v1/userinfo',
  jwks_url: 'https://www.googleapis.com/oauth2/v3/certs',
  scopes: ['openid', 'profile', 'email']
)
```

### Creating an OpenID Connect Credential

```ruby
# Basic OpenID Connect credential
credential = Adk::Auth::Credential.new(
  auth_type: :openid_connect,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET']
)

# With additional options
credential = Adk::Auth::Credential.new(
  auth_type: :openid_connect,
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
scheme = Adk::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
  scopes: ['openid', 'profile', 'email']
)

# 2. Configure the credential
credential = Adk::Auth::Credential.new(
  auth_type: :openid_connect,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET']
)

# 3. Configure a tool with the scheme and credential
tool = Adk::Tools::SomeTool.new(
  auth_scheme: scheme,
  auth_credential: credential
)

# 4. Set up a runner and register the tool
runner = Adk::Runner.new
runner.register_tool('example_tool', tool)

# 5. Start the runner in a Fiber
fiber = Fiber.new do
  runner.run(tool_name: 'example_tool', params: { /* tool parameters */ })
end

# 6. Initial call yields an authentication configuration
auth_config = fiber.resume

# 7. In a web application, handle the authentication
# 7a. Get the authorization URL
auth_url = auth_config.auth_uri

# 7b. Redirect the user to the authorization URL
# User authenticates and is redirected back to your redirect_uri
# Your application receives a callback with an authorization code

# 8. Resume the Fiber with the authorization code
auth_response = {
  auth_request_id: auth_config.auth_request_id,
  auth_response_uri: 'https://your-app.com/callback?code=12345&state=abcde'
}

# 9. Complete the operation
result = fiber.resume(auth_response)
```

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
scheme = Adk::Auth::Schemes::OpenIDConnect.new(
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
scheme = Adk::Auth::Schemes::OpenIDConnect.new(
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

scheme = Adk::Auth::Schemes::OpenIDConnect.new(
  discovery_url: "https://login.microsoftonline.com/#{tenant_id}/v2.0/.well-known/openid-configuration",
  scopes: ['openid', 'profile', 'email', 'offline_access']
)
```

### Auth0

```ruby
domain = 'your-domain.auth0.com'

scheme = Adk::Auth::Schemes::OpenIDConnect.new(
  discovery_url: "https://#{domain}/.well-known/openid-configuration",
  scopes: ['openid', 'profile', 'email']
)
```

## Security Considerations

- **Nonce Verification**: The library automatically adds a nonce parameter to prevent replay attacks
- **ID Token Validation**: Always verify the ID token signature, issuer, audience, and expiration
- **Scopes**: Request only the scopes your application needs
- **Secure Storage**: The ADK Ruby library automatically encrypts tokens stored in the session

## Advanced Features

### PKCE (Proof Key for Code Exchange)

```ruby
# PKCE is enabled by default
scheme = Adk::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
  use_pkce: true  # This is the default
)
```

### Prompt Parameter

Control the authentication experience using the prompt parameter:

```ruby
scheme = Adk::Auth::Schemes::OpenIDConnect.new(
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