# Authentication Overview

## Introduction

The ADK Ruby authentication system provides a comprehensive framework for handling authentication with external APIs. It supports various authentication methods including:

- API Key authentication
- HTTP Bearer token authentication
- OAuth2 authentication
- OpenID Connect (OIDC) authentication
- Service Account authentication

The system is designed to handle both interactive authentication flows (like OAuth2, which requires user consent) and non-interactive flows (like API Keys), with a unified interface.

## Core Concepts

### Authentication Schemes

An authentication scheme (`Adk::Auth::Scheme`) defines how an API expects credentials to be provided. Each scheme implements:

- How to apply authentication to requests
- How to exchange initial credentials for tokens (if applicable)
- How to refresh tokens (if applicable)
- How to build authorization URIs for interactive flows

The ADK Ruby library includes the following authentication schemes:

- `Adk::Auth::Schemes::APIKey`: For API key authentication (in header, query, or cookie)
- `Adk::Auth::Schemes::HTTPBearer`: For Bearer token authentication
- `Adk::Auth::Schemes::OAuth2`: For OAuth2 authentication flows
- `Adk::Auth::Schemes::OpenIDConnect`: For OpenID Connect authentication
- `Adk::Auth::Schemes::ServiceAccount`: For service account authentication
- `Adk::Auth::Schemes::GoogleServiceAccount`: For Google Cloud service accounts

### Credentials

A credential (`Adk::Auth::Credential`) contains the initial information needed to start authentication:

- API Keys
- OAuth2 client ID and client secret
- Bearer tokens
- Service account keys

Credentials can be provided directly or through environment variables, which is recommended for sensitive information.

### Token Exchange

For authentication methods like OAuth2, the initial credential must be exchanged for a token:

1. The initial credential (e.g., client ID and secret) is used to start the authentication flow
2. The flow results in an exchanged credential (`Adk::Auth::ExchangedCredential`)
3. The exchanged credential contains access tokens, refresh tokens, and expiry information

### Authentication Flows

#### Non-Interactive Flow (API Key, Bearer Token)

```ruby
# Create an API Key scheme
scheme = Adk::Auth::Schemes::APIKey.new(name: 'api_key', in: :header)

# Create a credential with the API key
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY']
)

# Configure a tool with the scheme and credential
tool = Adk::Tools::SomeTool.new(
  auth_scheme: scheme,
  auth_credential: credential
)

# The ADK automatically applies the API key to requests
result = tool.execute(params)
```

#### Interactive Flow (OAuth2, OIDC)

```ruby
# Create an OAuth2 scheme
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorization_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token',
  scopes: ['profile', 'email']
)

# Create a credential with client ID and secret
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET']
)

# Configure a runner with the tool, scheme, and credential
runner = Adk::Runner.new
runner.register_tool('example_tool', 
  Adk::Tools::SomeTool.new(
    auth_scheme: scheme,
    auth_credential: credential
  )
)

# Start the runner in a Fiber
fiber = Fiber.new do
  runner.run(tool_name: 'example_tool', params: {...})
end

# Initial call yields an authentication configuration
auth_config = fiber.resume

# Handle the authentication (in a web application)
# 1. Display auth_config.auth_uri to the user
# 2. User authenticates and is redirected back
# 3. Capture the authorization code from the callback

# Resume the Fiber with the authorization code
result = fiber.resume({
  auth_request_id: auth_config.auth_request_id,
  auth_response_uri: 'https://your-app.com/callback?code=12345&state=abcde'
})

# Now the operation completes with valid tokens
```

#### Service Account Flow

```ruby
# Create a Service Account scheme
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# Create a credential with the service account key
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('service-account.json'))
)

# Configure a tool with the scheme and credential
tool = Adk::Tools::GoogleCloudTool.new(
  auth_scheme: scheme,
  auth_credential: credential
)

# The ADK automatically exchanges for tokens and applies them
result = tool.execute(params)
```

## Security Considerations

The ADK Ruby library implements several security measures:

- Sensitive credentials are encrypted before storage
- Tokens are stored securely in the session state
- Access tokens have limited lifetimes
- Refresh tokens are handled securely
- Environment variable resolution protects sensitive values

## Next Steps

- [Authentication Configuration](./configuration) - How to configure authentication for different scenarios
- [API Key Authentication](./api_key) - Detailed guide for API key authentication
- [OAuth2 Authentication](./oauth2) - Complete guide for implementing OAuth2 flows
- [Token Lifecycle Management](./token_lifecycle) - Managing token expiration and refresh 