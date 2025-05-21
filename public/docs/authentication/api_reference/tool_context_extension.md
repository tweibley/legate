# Tool Context Authentication Extensions

## Overview

The `Adk::Auth::ToolContextExtension` module extends the `Adk::ToolContext` class with authentication-specific functionality, allowing tools to easily access and manage authentication credentials. This extension is critical for tools that need to authenticate with external APIs.

## Module Definition

```ruby
module Adk
  module Auth
    module ToolContextExtension
      # Authentication extensions for ToolContext
    end
  end
end
```

## Key Features

- Access to authentication credentials
- Token management and refresh
- Integration with interactive authentication flows
- Secure credential storage
- Support for all authentication schemes

## Usage

### Accessing Authentication Credentials

```ruby
# In a tool's implementation
def call(context, **params)
  # Get the configured credential for this tool
  credential = context.auth_credential
  
  # Use the credential for API requests
  api_key = credential.api_key
  
  # Make authenticated request
  # ...
end
```

### Managing Tokens

```ruby
# Get valid tokens for the current tool
tokens = context.get_valid_tokens
if tokens
  access_token = tokens[:access_token]
  # Use access token for API requests
end

# Request a new access token using a refresh token
new_tokens = context.refresh_tokens(tokens)
```

### Interactive Authentication

```ruby
# Check if an authentication response is available
auth_response = context.get_auth_response
if auth_response
  # Process the authentication response
  access_token = auth_response.access_token
  # Use the access token
end

# Request authentication from the user
auth_config = Adk::Auth::Config.new(
  scheme: oauth2_scheme,
  credential: oauth2_credential
)
context.request_auth(auth_config)
# Execution will yield here if interactive authentication is required
```

## Methods

### `auth_credential`

Retrieves the authentication credential configured for the current tool.

```ruby
credential = context.auth_credential
```

### `auth_scheme`

Retrieves the authentication scheme configured for the current tool.

```ruby
scheme = context.auth_scheme
```

### `get_valid_tokens`

Retrieves valid tokens for the current tool, refreshing them if necessary.

```ruby
tokens = context.get_valid_tokens(refresh: true)
```

### `refresh_tokens`

Refreshes the tokens for the current tool.

```ruby
new_tokens = context.refresh_tokens(tokens)
```

### `get_auth_response`

Checks if an authentication response is available after an interactive authentication flow.

```ruby
auth_response = context.get_auth_response
```

### `request_auth`

Requests authentication from the user, yielding execution if interactive authentication is required.

```ruby
context.request_auth(auth_config)
```

### `store_tokens`

Stores authentication tokens securely.

```ruby
context.store_tokens(
  access_token: 'access_token_value',
  refresh_token: 'refresh_token_value',
  expires_at: Time.now + 3600
)
```

## Integration with Tool Implementation

Here's a complete example of how to use the tool context extensions in a custom tool:

```ruby
class MyApiTool < Adk::Tool::FunctionTool
  def call(context, **params)
    # Try to get valid tokens
    tokens = context.get_valid_tokens(refresh: true)
    
    unless tokens
      # No valid tokens, check for auth response
      auth_response = context.get_auth_response
      
      if auth_response
        # Use tokens from auth response
        tokens = {
          access_token: auth_response.access_token,
          refresh_token: auth_response.refresh_token,
          expires_at: auth_response.expires_at
        }
        
        # Store tokens for future use
        context.store_tokens(tokens)
      else
        # Request authentication
        auth_config = Adk::Auth::Config.new(
          scheme: context.auth_scheme,
          credential: context.auth_credential
        )
        context.request_auth(auth_config)
        # Execution will yield here if interactive authentication is required
        return { status: 'authentication_required' }
      end
    end
    
    # Make authenticated API request
    conn = Excon.new('https://api.example.com')
    response = conn.get(
      path: '/data',
      headers: {
        'Authorization' => "Bearer #{tokens[:access_token]}"
      }
    )
    
    # Process response
    { result: JSON.parse(response.body) }
  end
end
```

## Error Handling

The tool context extensions can raise the following errors:

- `Adk::Auth::Error::CredentialNotConfiguredError`: No credential configured for the tool
- `Adk::Auth::Error::SchemeNotConfiguredError`: No scheme configured for the tool
- `Adk::Auth::Error::TokenRefreshError`: Failed to refresh tokens
- `Adk::Auth::Error::AuthenticationRequiredError`: Authentication is required but not available

## Related Classes

- [`Adk::ToolContext`](../../core_concepts/tool_context.md): The base tool context class
- [`Adk::Auth::Config`](./config.md): Authentication configuration
- [`Adk::Auth::TokenManager`](./token_manager.md): Token lifecycle management
- [`Adk::Auth::Scheme`](./scheme.md): Base class for authentication schemes 