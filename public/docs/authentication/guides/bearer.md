# HTTP Bearer Authentication

## Overview

HTTP Bearer authentication is a simple and widely used authentication scheme that involves sending a token, typically a JWT (JSON Web Token), in the `Authorization` header of HTTP requests. The ADK Ruby library provides built-in support for this authentication scheme through the `Adk::Auth::Schemes::HTTPBearer` class.

## Key Concepts

- **Bearer Token**: A security token that grants access to protected resources, which the bearer can use without proving possession of a cryptographic key
- **Authorization Header**: HTTP header used to send the bearer token in the format `Authorization: Bearer <token>`
- **Token Types**: Commonly a JWT, but can be any opaque string accepted by the API

## Setting Up Bearer Authentication

### Step 1: Create the Authentication Scheme

```ruby
# Create an HTTP Bearer scheme
bearer_scheme = Adk::Auth::Schemes::HTTPBearer.new
```

### Step 2: Create the Credential

```ruby
# Option 1: Directly provide the token
credential = Adk::Auth::Credential.new(
  bearer_token: 'your_bearer_token_here'
)

# Option 2: Use an environment variable (recommended)
credential = Adk::Auth::Credential.new(
  bearer_token: ENV['API_BEARER_TOKEN']
)

# Option 3: Reference an environment variable by name
credential = Adk::Auth::Credential.new(
  bearer_token_env: 'API_BEARER_TOKEN'
)
```

### Step 3: Configure a Tool with Bearer Authentication

```ruby
# Configure an OpenAPI toolset
toolset = Adk::Tool::OpenAPIToolset.new(
  spec_path: 'path/to/openapi_spec.json',
  auth_scheme: bearer_scheme,
  auth_credential: credential
)

# Or configure a custom tool
class MyApiTool < Adk::Tool::FunctionTool
  def initialize
    super(
      auth_scheme: bearer_scheme,
      auth_credential: credential
    )
  end
  
  def call(context, **params)
    # Use authentication through the context
    # ...
  end
end
```

## Using Bearer Authentication in API Requests

### With OpenAPI Toolset

When using an OpenAPI toolset configured with Bearer authentication, the authentication is handled automatically:

```ruby
# The Authorization header is automatically added
result = toolset.execute_operation('getResource', { id: '123' })
```

### With Custom Tools

For custom function tools, you can access the bearer token through the tool context:

```ruby
def call(context, **params)
  # Get the bearer token
  credential = context.auth_credential
  bearer_token = credential.bearer_token
  
  # Create an authenticated connection
  conn = Excon.new('https://api.example.com')
  response = conn.get(
    path: '/protected-resource',
    headers: {
      'Authorization' => "Bearer #{bearer_token}"
    }
  )
  
  # Process the response
  JSON.parse(response.body)
end
```

### Using the Excon Middleware

You can also use the Excon middleware to automatically handle Bearer authentication:

```ruby
# Create middleware for Bearer authentication
middleware = Adk::Auth.create_middleware(
  scheme: bearer_scheme,
  credential: credential
)

# Create a connection with the middleware
connection = Excon.new('https://api.example.com', 
  middlewares: [middleware])

# Make authenticated requests
response = connection.get(path: '/protected-resource')
```

Or use the connection helper:

```ruby
# Create an authenticated connection directly
connection = Adk::Auth.create_connection(
  'https://api.example.com',
  scheme: bearer_scheme,
  credential: credential
)

# Make authenticated requests
response = connection.get(path: '/protected-resource')
```

## Token Management

Unlike OAuth2 or OIDC, HTTP Bearer authentication does not include built-in token refresh mechanisms. If your bearer token expires, you will need to obtain a new one externally and update your credential:

```ruby
# Update the bearer token
credential.bearer_token = new_token

# Or update the environment variable referenced by bearer_token_env
ENV['API_BEARER_TOKEN'] = new_token
```

## Security Considerations

- Bearer tokens should be treated as sensitive information, similar to passwords
- Use HTTPS for all requests to prevent token interception
- Store tokens securely, preferably in environment variables rather than in code
- Use short-lived tokens where possible to minimize risk of token compromise
- Consider using OAuth2 or OIDC if you need more advanced features like token refresh and revocation

## Complete Example

Here's a complete example of using Bearer authentication with the ADK:

```ruby
require 'adk'
require 'excon'

# Create the scheme and credential
bearer_scheme = Adk::Auth::Schemes::HTTPBearer.new
credential = Adk::Auth::Credential.new(
  bearer_token_env: 'API_BEARER_TOKEN'
)

# Create a custom tool
class UserProfileTool < Adk::Tool::FunctionTool
  def initialize
    super(
      name: 'get_user_profile',
      description: 'Gets the current user profile',
      auth_scheme: bearer_scheme,
      auth_credential: credential
    )
  end
  
  def call(context, **params)
    # Create an authenticated connection
    connection = Adk::Auth.create_connection(
      'https://api.example.com',
      scheme: context.auth_scheme,
      credential: context.auth_credential
    )
    
    # Make the authenticated request
    response = connection.get(path: '/user/profile')
    
    # Check for authentication errors
    if response.status == 401
      { status: 'error', message: 'Authentication failed. Bearer token may be invalid or expired.' }
    else
      { status: 'success', profile: JSON.parse(response.body) }
    end
  end
end

# Initialize and use the tool
tool = UserProfileTool.new
runner = Adk::Runner.new
result = runner.run(tool)
puts result
```

## Related Topics
- [Adk::Auth::Schemes::HTTPBearer API Reference](../api_reference/schemes/http_bearer)
- [Excon Middleware for Authentication](../api_reference/excon_middleware) 