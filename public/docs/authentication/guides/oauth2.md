# OAuth2 Authentication

OAuth2 is a powerful authentication framework that allows users to authorize applications to access their accounts on other services without sharing their credentials. The ADK Ruby library provides comprehensive support for OAuth2 authentication flows.

## Overview

OAuth2 is an industry-standard protocol for authorization that enables secure API access without sharing passwords. The ADK Ruby library supports the following OAuth2 flows:

- **Authorization Code Flow**: The most common flow for web applications, involving a browser-based user consent
- **Client Credentials Flow**: Used for server-to-server authentication
- **Password Flow**: Used for trusted applications that can collect user credentials directly

## Configuration

### Creating an OAuth2 Scheme

```ruby
# Basic OAuth2 scheme with required parameters
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['profile', 'email', 'data:read']
)

# OAuth2 scheme with additional options
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['profile', 'email', 'data:read'],
  use_pkce: true,  # Use PKCE for enhanced security (default: true)
  additional_params: {
    'access_type' => 'offline',  # Request a refresh token
    'prompt' => 'consent'        # Force the consent screen to appear
  },
  revocation_url: 'https://auth.example.com/revoke'  # For token revocation
)
```

### Creating an OAuth2 Credential

```ruby
# Basic OAuth2 credential with client ID and secret
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET']
)

# With additional options
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET'],
  additional_params: {
    'client_authentication' => 'body'  # Send client credentials in request body
  }
)
```

## Authentication Flows

### Authorization Code Flow

The authorization code flow is an interactive flow that requires user authentication and consent:

```ruby
# 1. Configure the OAuth2 scheme and credential
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['profile', 'email']
)

credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET']
)

# 2. Configure a tool with the scheme and credential
tool = Adk::Tools::SomeTool.new(
  auth_scheme: scheme,
  auth_credential: credential
)

# 3. Set up a runner and register the tool
runner = Adk::Runner.new
runner.register_tool('example_tool', tool)

# 4. Start the runner in a Fiber
fiber = Fiber.new do
  runner.run(tool_name: 'example_tool', params: { /* tool parameters */ })
end

# 5. Initial call yields an authentication configuration
auth_config = fiber.resume

# 6. In a web application, handle the authentication
# 6a. Get the authorization URL
auth_url = auth_config.auth_uri

# 6b. Redirect the user to the authorization URL
# User authenticates and is redirected back to your redirect_uri
# Your application receives a callback with an authorization code

# 7. Resume the Fiber with the authorization code
auth_response = {
  auth_request_id: auth_config.auth_request_id,
  auth_response_uri: 'https://your-app.com/callback?code=12345&state=abcde'
}

# 8. Complete the operation
result = fiber.resume(auth_response)
```

### Client Credentials Flow

The client credentials flow is a non-interactive flow used for server-to-server authentication:

```ruby
# 1. Configure the OAuth2 scheme
scheme = Adk::Auth::Schemes::OAuth2.new(
  token_url: 'https://auth.example.com/token',
  scopes: ['api:access']
)

# 2. Configure the credential
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET'],
  grant_type: 'client_credentials'  # Specify client credentials flow
)

# 3. Configure a tool with the scheme and credential
tool = Adk::Tools::SomeTool.new(
  auth_scheme: scheme,
  auth_credential: credential
)

# 4. Use the tool - the token exchange happens automatically
result = tool.execute(params)
```

## Token Refresh

OAuth2 access tokens typically expire after a short period. The ADK Ruby library automatically handles token refresh:

```ruby
# Configure the scheme with a scope that returns a refresh token
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['profile', 'email', 'offline_access'],  # offline_access requests a refresh token
  additional_params: {
    'access_type' => 'offline'  # For Google OAuth2, request a refresh token
  }
)

# Use the tool - the ADK will automatically refresh the token when needed
result = tool.execute(params)
```

## Advanced Features

### PKCE (Proof Key for Code Exchange)

PKCE enhances security for public clients by preventing authorization code interception attacks:

```ruby
# PKCE is enabled by default
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['profile', 'email'],
  use_pkce: true  # This is the default
)
```

### Token Revocation

When you no longer need an access token, you can revoke it:

```ruby
# Configure the scheme with a revocation URL
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  revocation_url: 'https://auth.example.com/revoke',
  scopes: ['profile', 'email']
)

# Revoke a token
token_manager = Adk::Auth::TokenManager.new
token_manager.revoke_token(token, credential)
```

## Provider-Specific Configurations

### Google OAuth2

```ruby
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://accounts.google.com/o/oauth2/auth',
  token_url: 'https://oauth2.googleapis.com/token',
  scopes: ['https://www.googleapis.com/auth/userinfo.email', 
           'https://www.googleapis.com/auth/userinfo.profile'],
  additional_params: {
    'access_type' => 'offline',
    'prompt' => 'consent'  # Force consent screen to appear
  }
)
```

### GitHub OAuth2

```ruby
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://github.com/login/oauth/authorize',
  token_url: 'https://github.com/login/oauth/access_token',
  scopes: ['user', 'repo']
)
```

### Microsoft Azure OAuth2

```ruby
tenant_id = 'common'  # Use 'common' for multi-tenant, or a specific tenant ID

scheme = Adk::Auth::Schemes::OAuth2.new(
  authorization_url: "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/authorize",
  token_url: "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token",
  scopes: ['user.read', 'offline_access']
)
```

## Security Considerations

- **Client Secret Protection**: Always store client secrets securely, preferably in environment variables.
- **HTTPS**: Ensure all OAuth2 endpoints use HTTPS to protect token transmission.
- **Use PKCE**: Enable PKCE (enabled by default) for enhanced security, especially for mobile or desktop applications.
- **Scoped Tokens**: Request only the scopes your application needs.
- **Token Storage**: The ADK Ruby library automatically encrypts tokens stored in the session.

## Troubleshooting

If you encounter issues with OAuth2 authentication:

- Check that all URLs and credentials are correct
- Verify that redirect URIs exactly match those registered with the provider
- Ensure scopes are properly formatted and allowed by the provider
- See the [OAuth2 Troubleshooting Guide](../troubleshooting/oauth2_issues) for detailed solutions

## Related Topics

- [OpenID Connect](./oidc) - Learn about OpenID Connect, an identity layer built on top of OAuth2
- [Token Lifecycle Management](./token_lifecycle) - Advanced token management techniques
- [Secure Credential Storage](./secure_storage) - Best practices for credential security

## Next Steps

- [OpenID Connect](./oidc): Learn about OpenID Connect, an identity layer built on top of OAuth2
- [Token Lifecycle Management](./token_lifecycle): Advanced token management techniques
- [Secure Credential Storage](./secure_storage): Best practices for credential security 