# API Key Authentication

API Keys are one of the simplest forms of authentication, commonly used for server-to-server API access. The ADK Ruby library provides comprehensive support for API Key authentication in various formats.

## Overview

API Key authentication works by including a key in the request, typically in one of three locations:

- **Header**: The API key is added as an HTTP header (most common)
- **Query Parameter**: The API key is added to the URL query string
- **Cookie**: The API key is included in a cookie

## Basic Setup

### Session Service and Token Store

For enhanced functionality and token management, you can set up a session service and token store:

```ruby
# Create session service for token storage
session_service = ADK::SessionService::InMemory.new

# Create a basic token store for caching
token_store = ADK::Auth::TokenStore.new(session_service)
```

### Creating an API Key Scheme

```ruby
# Create an API Key scheme
scheme = ADK::Auth::Schemes::ApiKey.new
```

### Creating an API Key Credential

```ruby
# Direct API key value
credential = ADK::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'your-api-key-value'
)

# API key from environment variable (recommended for security)
credential = ADK::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY']
)

# With custom location and name (e.g., for query parameter)
credential = ADK::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY'],
  location: 'query',          # Options: 'header', 'query', 'cookie'
  name: 'api_key'            # Parameter name in the chosen location
)
```

## Usage Examples

### Tool-Based Approach

The most straightforward way to use API key authentication is with ADK tools:

```ruby
# Create an API Key scheme
scheme = ADK::Auth::Schemes::ApiKey.new

# Create a credential with the API key
credential = ADK::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY'],
  location: 'query',
  name: 'api_key'
)

# Configure a tool with the scheme and credential
tool = ADK::Tools::YourTool.new(
  auth_scheme: scheme,
  auth_credential: credential
)

# The API key will be automatically applied
result = tool.execute(params)
```

### Middleware Approach

For more direct HTTP client usage, you can use the ADK Auth middleware:

```ruby
# Create a connection with API key middleware
connection = ADK::Auth.create_api_key_connection(
  'https://api.example.com',
  api_key: ENV['API_KEY'],
  location: 'query',
  name: 'api_key',
  token_store: token_store  # Optional
)

# Make requests through the middleware
response = connection.request(
  method: :get,
  path: '/api/endpoint',
  query: { param: 'value' }
)
```

### Manual Authentication Application

For cases where you need more control, you can manually apply authentication:

```ruby
# Create a request hash
request = {
  method: :get,
  path: '/api/endpoint',
  query: { param: 'value' },
  headers: {}
}

# Apply authentication manually
request_with_auth = ADK::Auth::ToolIntegration.apply_authentication(
  request,
  scheme,
  credential,
  token_store  # Optional
)

# Use the authenticated request with your HTTP client
connection = Excon.new('https://api.example.com')
response = connection.request(request_with_auth)
```

### Direct HTTP Client Usage

For the simplest cases, you can directly include the API key:

```ruby
# Create connection
connection = Excon.new('https://api.example.com')

# Include API key in query parameters
response = connection.request(
  method: :get,
  path: '/api/endpoint',
  query: {
    api_key: ENV['API_KEY'],
    param: 'value'
  }
)
```

## API Key Security Best Practices

1. **Environment Variables**: Store API keys in environment variables
2. **Token Store**: Use token store for caching and management when appropriate
3. **Secure Transport**: Always use HTTPS for API requests
4. **Key Rotation**: Update API keys periodically
5. **Minimal Permissions**: Use keys with the minimum required access

## Troubleshooting

### Common Issues

1. **Authentication Failure**: Verify the API key location and name match the API requirements
2. **Token Store Issues**: Ensure session service is properly initialized
3. **Middleware Configuration**: Check connection parameters when using `create_api_key_connection`

### Debugging Tips

```ruby
# Debug authentication application
request = { headers: {}, query: {} }
modified_request = scheme.apply_to_request(request, credential)
puts "Modified request: #{modified_request.inspect}"

# Debug middleware setup
connection = ADK::Auth.create_api_key_connection(
  'https://api.example.com',
  api_key: ENV['API_KEY'],
  location: 'query',
  name: 'api_key',
  debug: true  # Enable debug logging
)
```

## Next Steps

- [Authentication Overview](./overview): Return to the overview of authentication
- [HTTP Bearer Authentication](./bearer): Learn about Bearer token authentication
- [OAuth2 Authentication](./oauth2): Implement OAuth2 authentication flows 