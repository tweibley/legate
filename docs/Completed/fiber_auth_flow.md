# Fiber-Based Authentication Flow

## Overview

The ADK Ruby library provides a fiber-based authentication flow that allows tools to integrate with authentication providers like OAuth2 and OpenID Connect (OIDC) in a way that supports interactive authentication, where execution can pause to wait for user authorization and then resume once authentication is complete.

This approach offers several advantages:

1. **Non-blocking execution**: Tools can pause execution during authentication and resume once complete
2. **Seamless API integration**: Authentication flows are abstracted away from tool implementation
3. **User experience improvements**: Supports launching browsers, handling callbacks, and displaying feedback
4. **Token lifecycle management**: Integrated with the TokenManager for automatic token refreshing and reuse

## Core Components

### Auth::Coordinator

The `Coordinator` base class manages the authentication flow using Ruby's `Fiber` to allow for pausing and resuming execution during authentication.

Key responsibilities:
- Initializing a fiber for authentication process
- Yielding auth requests when user interaction is needed
- Resuming execution when responses are received
- Managing timeouts and error handling
- Supporting cancellation of in-progress authentication flows

Specialized coordinators are provided for different authentication schemes:
- `OAuth2Coordinator`: Manages OAuth2 authorization code flows
- `OIDCCoordinator`: Extends OAuth2 with OpenID Connect specific functionality

### Auth::Runner

The `Runner` class provides the execution environment for running tasks with authentication support:

Key responsibilities:
- Running tasks within fibers
- Handling authentication requests yielded by coordinators
- Managing active authentication flows
- Providing the auth_session method to tools
- Integrating with the TokenManager for token acquisition and reuse

### ToolContextExtension

The `with_authentication` method is added to the `ToolContext` class, allowing tools to execute code in a fiber with authentication support.

## Authentication Flow

The authentication flow follows these steps:

1. A tool calls `context.auth_session(scheme, credential)` to request a token
2. If a valid token is in the cache, it's returned immediately
3. If no valid token exists, a coordinator is created and started
4. The coordinator yields an authentication request
5. The runner captures this request and yields it to the calling code
6. The calling code presents the authentication request to the user (e.g., opening a browser)
7. When the user completes authentication, a response is passed to `handle_auth_response`
8. The response is forwarded to the appropriate coordinator
9. The coordinator processes the response and completes the token exchange
10. The token is cached and returned to the original `auth_session` call
11. Execution continues with the authenticated token

## Usage Examples

### Basic Usage

```ruby
# Within a tool execution method:
def execute
  # Use with_authentication to create a fiber context with auth support
  context.with_authentication do
    # Define an OAuth2 scheme
    oauth2_scheme = ADK::Auth::Schemes::OAuth2.new(
      authorization_url: 'https://example.com/auth',
      token_url: 'https://example.com/token',
      scopes: ['read', 'write']
    )
    
    # Define a credential
    credential = ADK::Auth::Credential.new(
      auth_type: :oauth2,
      client_id: 'client-id',
      client_secret: 'client-secret'
    )
    
    # Get a token - this will yield the fiber if authentication is needed
    token = context.auth_session(oauth2_scheme, credential)
    
    # Use the token to make API calls
    api_client.call_api(token)
  end
end
```

### Interactive Web Server Example

For CLIs that need to handle authentication callbacks automatically, a small web server can be used:

```ruby
def run_with_server
  # Create a web server to handle OAuth2 callbacks
  server = create_web_server()
  
  begin
    # Start the server
    server_thread = Thread.new { server.start }
    
    # Use with_authentication and provide a handler for auth requests
    result = context.with_authentication do |auth_request|
      # Open browser when authorization is needed
      if auth_request[:auth_request][:type] == 'authorization_request'
        Launchy.open(auth_request[:auth_request][:url])
      end
      
      # Return nil to continue waiting for callback
      nil
    end
    
    # Task execution runs here after authentication
    make_api_call_with_token(result)
  ensure
    # Clean up the server
    server.stop
    server_thread.join
  end
end
```

## Advanced Features

### Token Reuse

Tokens are automatically cached by the TokenManager, so subsequent calls to `auth_session` with the same scheme and credential will reuse the token without requiring re-authentication.

### Token Refresh

If a token is expired but has a refresh token, the TokenManager will automatically attempt to refresh it before starting a new authentication flow.

### Handling Authentication Errors

Authentication errors are propagated through the fiber system:

```ruby
begin
  context.with_authentication do
    token = context.auth_session(scheme, credential)
    # Use token here
  end
rescue ADK::Auth::Error => e
  # Handle authentication errors
  puts "Authentication failed: #{e.message}"
end
```

## Integration with TokenManager

The fiber-based authentication system is fully integrated with the TokenManager:

- Tokens acquired through the fiber-based flow are stored in the TokenManager's cache
- The TokenManager's token lifecycle events (acquired, refreshed, invalidated) are triggered appropriately
- Token revocation can be performed through the TokenManager and will be respected by the fiber-based flow

## Conclusion

The fiber-based authentication system provides a powerful, flexible way to integrate authentication into tools, offering a great user experience without complicating the tool implementation.

For working examples, see:
- `examples/auth/fiber_auth_example.rb` - Basic OAuth2 example
- `examples/auth/fiber_oidc_example.rb` - OpenID Connect example 