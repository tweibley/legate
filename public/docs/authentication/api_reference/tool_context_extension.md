# Tool Context Authentication Extensions

## Overview

The `Legate::Auth::ToolContextExtension` module extends the `Legate::ToolContext` class with authentication-specific functionality, allowing tools to easily access and manage authentication credentials. This extension is critical for tools that need to authenticate with external APIs.

## Module Definition

```ruby
module Legate
  module Auth
    module ToolContextExtension
      # Authentication extensions for ToolContext
    end
  end
end
```

## Key Features

- Access to authentication runners and token stores
- Managed authentication sessions
- Integration with interactive authentication flows
- Support for all authentication schemes

## Methods

### `auth_runner`

Returns the authentication runner for managing authentication flows.

**Returns:**
- The authentication runner instance

**Examples:**

```ruby
# In a tool's implementation
runner = context.auth_runner
```

### `get_token_store`

Returns the token store for the current session.

**Returns:**
- Legate::Auth::TokenStore: The token store

**Examples:**

```ruby
token_store = context.get_token_store
```

### `with_authentication`

Wraps a block with authentication handling. If authentication is required, it will initiate the authentication flow and retry the block once authentication is complete.

**Parameters:**
- `&block` (Block): The block to execute with authentication

**Examples:**

```ruby
# In a tool's implementation
def perform_execution(params, context)
  context.with_authentication do
    # Make authenticated API calls here
    # If auth fails, the flow will be initiated automatically
    response = make_api_request(context)
    { status: :success, result: response }
  end
end
```

### `auth_session`

Creates an authentication session for the given scheme and credential.

**Parameters:**
- `scheme` (Legate::Auth::Scheme): The authentication scheme
- `credential` (Legate::Auth::Credential): The credential to use
- `**options` (Hash): Additional options for the authentication session

**Returns:**
- An authentication session object

**Examples:**

```ruby
session = context.auth_session(oauth2_scheme, oauth2_credential)
```

### `handle_auth_response`

Handles an authentication response from an interactive authentication flow (e.g., OAuth2 callback).

**Parameters:**
- `request_id` (String): The authentication request ID
- `response` (Hash): The authentication response data

**Examples:**

```ruby
# When the OAuth2 callback is received
context.handle_auth_response('req_123456', {
  code: params[:code],
  state: params[:state]
})
```

### `cancel_auth_flow`

Cancels an in-progress authentication flow.

**Parameters:**
- `request_id` (String): The authentication request ID to cancel
- `reason` (String, optional): The reason for cancellation (default: nil)

**Examples:**

```ruby
# Cancel an authentication flow
context.cancel_auth_flow('req_123456', 'User declined')
```

## Integration with Tool Implementation

Here's a complete example of how to use the tool context extensions in a custom tool:

```ruby
class MyApiTool < Legate::Tool
  def perform_execution(params, context)
    context.with_authentication do
      # Get a token store for caching
      token_store = context.get_token_store

      # Create an auth session
      session = context.auth_session(
        Legate::Auth::Schemes::OAuth2.new(
          authorization_url: 'https://auth.example.com/authorize',
          token_url: 'https://auth.example.com/token'
        ),
        Legate::Auth::Credential.new(
          auth_type: :oauth2,
          client_id: ENV['CLIENT_ID'],
          client_secret: ENV['CLIENT_SECRET']
        )
      )

      # Make authenticated API request
      conn = Excon.new('https://api.example.com')
      response = conn.get(path: '/data')

      # Process response
      { result: JSON.parse(response.body) }
    end
  end
end
```

## Related Classes

- [`Legate::Auth::Config`](./config): Authentication configuration
- [`Legate::Auth::TokenManager`](./token_manager): Token lifecycle management
- [`Legate::Auth::Scheme`](./scheme): Base class for authentication schemes
