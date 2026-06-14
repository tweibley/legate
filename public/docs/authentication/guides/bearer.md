# HTTP Bearer Authentication

## Overview

HTTP Bearer authentication is a simple and widely used authentication scheme that involves sending a token, typically a JWT (JSON Web Token), in the `Authorization` header of HTTP requests. The Legate Ruby library provides built-in support for this authentication scheme through the `Legate::Auth::Schemes::HTTPBearer` class.

## Key Concepts

- **Bearer Token**: A security token that grants access to protected resources, which the bearer can use without proving possession of a cryptographic key
- **Authorization Header**: HTTP header used to send the bearer token in the format `Authorization: Bearer <token>`
- **Token Types**: Commonly a JWT, but can be any opaque string accepted by the API

## Setting Up Bearer Authentication

### Step 1: Create the Authentication Scheme

```ruby
# Create an HTTP Bearer scheme
bearer_scheme = Legate::Auth::Schemes::HTTPBearer.new
```

### Step 2: Create the Credential

```ruby
# Option 1: Directly provide the token
credential = Legate::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'your_bearer_token_here'
)

# Option 2: Read the token from an environment variable at runtime
credential = Legate::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: ENV['API_BEARER_TOKEN']
)

# Option 3: Reference an environment variable with the ENV: prefix (resolved lazily)
credential = Legate::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'ENV:API_BEARER_TOKEN'
)
```

### Step 3: Attach Bearer Authentication to a Connection

```ruby
# Create an authenticated Excon connection using the helper
connection = Legate::Auth.create_connection('https://api.example.com',
  scheme: bearer_scheme,
  credential: credential
)

# The Authorization header is applied automatically
response = connection.get(path: '/protected-resource')
```

## Using Bearer Authentication in API Requests

### Reading the token from a credential

You can read the bearer token from a credential using the `[]` accessor
(which resolves `ENV:` references):

```ruby
bearer_token = credential[:bearer_token]

conn = Excon.new('https://api.example.com')
response = conn.get(
  path: '/protected-resource',
  headers: { 'Authorization' => "Bearer #{bearer_token}" }
)

JSON.parse(response.body)
```

### Using the Excon Middleware

You can also build the middleware explicitly and attach it via the connection helper:

```ruby
# Create middleware for Bearer authentication
middleware = Legate::Auth.create_middleware(
  scheme: bearer_scheme,
  credential: credential
)
# (create_middleware returns a configured ExconMiddleware instance; the
# connection helpers below wire it onto a connection for you.)
```

Or use the connection helper directly:

```ruby
# Create an authenticated connection directly
connection = Legate::Auth.create_connection(
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
# Update the bearer token on the credential
credential[:bearer_token] = new_token

# Or, if you reference it via 'ENV:API_BEARER_TOKEN', update the env var
ENV['API_BEARER_TOKEN'] = new_token
```

## Security Considerations

- Bearer tokens should be treated as sensitive information, similar to passwords
- Use HTTPS for all requests to prevent token interception
- Store tokens securely, preferably in environment variables rather than in code
- Use short-lived tokens where possible to minimize risk of token compromise
- Consider using OAuth2 or OIDC if you need more advanced features like token refresh and revocation

## Complete Example

Here's a complete example of using Bearer authentication with the Legate:

```ruby
require 'legate'
require 'excon'

# Create the scheme and credential
bearer_scheme = Legate::Auth::Schemes::HTTPBearer.new
credential = Legate::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: 'ENV:API_BEARER_TOKEN'
)

# Create a custom tool
class UserProfileTool < Legate::Tool
  tool_description 'Gets the current user profile'

  def perform_execution(params, context)
    # Create an authenticated connection
    bearer_scheme = Legate::Auth::Schemes::HTTPBearer.new
    credential = Legate::Auth::Credential.new(
      auth_type: :http_bearer,
      bearer_token: 'ENV:API_BEARER_TOKEN'
    )

    connection = Legate::Auth.create_connection(
      'https://api.example.com',
      scheme: bearer_scheme,
      credential: credential
    )

    # Make the authenticated request
    response = connection.get(path: '/user/profile')

    # Check for authentication errors
    if response.status == 401
      { status: :error, error_message: 'Authentication failed. Bearer token may be invalid or expired.' }
    else
      { status: :success, result: JSON.parse(response.body) }
    end
  end
end
```

## Related Topics
- [Legate::Auth::Schemes::HTTPBearer API Reference](../api_reference/schemes/http_bearer)
- [Excon Middleware for Authentication](../api_reference/excon_middleware) 