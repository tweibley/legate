# API Key Authentication

API Keys are one of the simplest forms of authentication, commonly used for server-to-server API access. The ADK Ruby library provides comprehensive support for API Key authentication in various formats.

## Overview

API Key authentication works by including a key in the request, typically in one of three locations:

- **Header**: The API key is added as an HTTP header (most common)
- **Query Parameter**: The API key is added to the URL query string
- **Cookie**: The API key is included in a cookie

## Configuration

### Creating an API Key Scheme

```ruby
# Create an API Key scheme with default settings (header-based)
scheme = Adk::Auth::Schemes::ApiKey.new

# Customize with specific parameters
scheme = Adk::Auth::Schemes::ApiKey.new
```

### Creating an API Key Credential

```ruby
# Direct API key value
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'your-api-key-value'
)

# API key from environment variable (recommended for security)
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY']
)

# With custom location and name
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY'],
  location: 'header',          # Options: 'header', 'query', 'cookie'
  name: 'X-Custom-API-Key'     # Default: 'X-API-Key' for header
)
```

## Usage Examples

### Basic Usage with Default Settings (Header)

```ruby
# Create an API Key scheme
scheme = Adk::Auth::Schemes::ApiKey.new

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

# The API key will be automatically applied as an 'X-API-Key' header
result = tool.execute(params)
```

### Query Parameter API Key

```ruby
# Create a credential with query parameter configuration
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY'],
  location: 'query',
  name: 'api_key'
)

# Configure a tool with the scheme and credential
tool = Adk::Tools::SomeTool.new(
  auth_scheme: Adk::Auth::Schemes::ApiKey.new,
  auth_credential: credential
)

# The API key will be automatically applied as '?api_key=value' in the URL
result = tool.execute(params)
```

### Cookie-based API Key

```ruby
# Create a credential with cookie configuration
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY'],
  location: 'cookie',
  name: 'session_token'
)

# Configure a tool with the scheme and credential
tool = Adk::Tools::SomeTool.new(
  auth_scheme: Adk::Auth::Schemes::ApiKey.new,
  auth_credential: credential
)

# The API key will be automatically applied as a cookie
result = tool.execute(params)
```

## API Key Rotation and Security

For enhanced security:

1. **Use Environment Variables**: Store API keys in environment variables rather than hardcoding them
2. **Rotate Keys Regularly**: Update your API keys periodically
3. **Use Specific Permissions**: Use API keys with the minimum required permissions
4. **Monitor Usage**: Keep track of API key usage for suspicious activity

To update an API key:

```ruby
# Create a new credential with the updated API key
new_credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['NEW_API_KEY'],
  location: credential.location,
  name: credential.name
)

# Update the tool with the new credential
tool.auth_credential = new_credential
```

## Troubleshooting

### Common Issues

1. **API Key Not Applied**: Check that the location ('header', 'query', 'cookie') matches what the API expects
2. **Wrong Header Name**: Verify the API key header name required by the service
3. **Expired or Invalid Key**: Confirm the API key is valid and hasn't expired
4. **Missing Environment Variable**: Ensure the environment variable is set correctly

### Debugging

To debug API key application:

```ruby
# Create a scheme and credential
scheme = Adk::Auth::Schemes::ApiKey.new
credential = Adk::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY']
)

# Create a sample request
request = { headers: {} }

# Apply the API key manually to see the result
modified_request = scheme.apply_to_request(request, credential)
puts "Modified request: #{modified_request.inspect}"
```

## Next Steps

- [Authentication Overview](./overview.md): Return to the overview of authentication
- [HTTP Bearer Authentication](./bearer.md): Learn about Bearer token authentication
- [OAuth2 Authentication](./oauth2.md): Implement OAuth2 authentication flows 