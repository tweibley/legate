# Adk::Auth::Config

The `Config` class represents the configuration for interactive authentication flows. It includes all the necessary information to initiate, track, and complete an authentication process that requires user interaction.

## Overview

In interactive authentication flows like OAuth2 or OpenID Connect, the user needs to be redirected to an authentication provider to authenticate and grant permissions. The `Config` class encapsulates all the details needed for this interaction, including the authentication URI, request ID, and callback handling.

## Class Methods

### `new`

Creates a new authentication configuration instance.

**Parameters:**
- `auth_uri` (String): The URI to redirect the user to for authentication
- `auth_request_id` (String): A unique identifier for this authentication request
- `callback_params` (Hash, optional): Parameters to include in the callback
- `kwargs` (Hash, optional): Additional configuration options

**Examples:**

```ruby
# Create a basic authentication configuration
config = Adk::Auth::Config.new(
  auth_uri: 'https://auth.example.com/authorize?client_id=123&redirect_uri=https://app.example.com/callback',
  auth_request_id: 'req_123456'
)

# With additional callback parameters
config = Adk::Auth::Config.new(
  auth_uri: 'https://auth.example.com/authorize?client_id=123&redirect_uri=https://app.example.com/callback',
  auth_request_id: 'req_123456',
  callback_params: {
    state: 'abc123',
    nonce: 'xyz789'
  }
)
```

## Instance Methods

### `auth_uri`

Returns the URI that the user should be redirected to for authentication.

**Returns:**
- String: The authentication URI

**Examples:**

```ruby
config = Adk::Auth::Config.new(
  auth_uri: 'https://auth.example.com/authorize?client_id=123',
  auth_request_id: 'req_123456'
)

puts config.auth_uri
# => "https://auth.example.com/authorize?client_id=123"
```

### `auth_request_id`

Returns the unique identifier for this authentication request.

**Returns:**
- String: The authentication request ID

**Examples:**

```ruby
config = Adk::Auth::Config.new(
  auth_uri: 'https://auth.example.com/authorize',
  auth_request_id: 'req_123456'
)

puts config.auth_request_id
# => "req_123456"
```

### `callback_params`

Returns the parameters to be included in the callback.

**Returns:**
- Hash: The callback parameters

**Examples:**

```ruby
config = Adk::Auth::Config.new(
  auth_uri: 'https://auth.example.com/authorize',
  auth_request_id: 'req_123456',
  callback_params: {
    state: 'abc123',
    nonce: 'xyz789'
  }
)

puts config.callback_params
# => {:state=>"abc123", :nonce=>"xyz789"}
```

### `[]` (accessor)

Provides access to any configuration attribute.

**Parameters:**
- `key` (Symbol, String): The name of the attribute to access

**Returns:**
- Object: The value of the attribute

**Examples:**

```ruby
config = Adk::Auth::Config.new(
  auth_uri: 'https://auth.example.com/authorize',
  auth_request_id: 'req_123456',
  custom_option: 'custom_value'
)

puts config[:custom_option]
# => "custom_value"
```

### `to_h`

Converts the configuration to a hash.

**Returns:**
- Hash: A hash representation of the configuration

**Examples:**

```ruby
config = Adk::Auth::Config.new(
  auth_uri: 'https://auth.example.com/authorize',
  auth_request_id: 'req_123456',
  callback_params: {
    state: 'abc123',
    nonce: 'xyz789'
  }
)

puts config.to_h
# => {auth_uri: "https://auth.example.com/authorize", auth_request_id: "req_123456", callback_params: {state: "abc123", nonce: "xyz789"}}
```

## Usage in Authentication Flows

The `Config` class is a key component in interactive authentication flows:

1. **Generation**: An authentication scheme (like OAuth2) generates a `Config` instance
2. **User Redirection**: The application redirects the user to the `auth_uri`
3. **Callback Handling**: When the user completes authentication, the provider redirects back to the application with an authorization code or token
4. **Request Matching**: The application matches the callback to the original request using the `auth_request_id`

Here's an example of how it's used in a typical OAuth2 flow:

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

# 2. Generate an authentication configuration
config = scheme.generate_auth_config(
  credential, 
  callback_url: 'https://app.example.com/callback'
)

# 3. In a web application, redirect the user to the auth URI
# redirect_to config.auth_uri

# 4. When the user is redirected back, the application processes the callback
auth_response = {
  auth_request_id: config.auth_request_id,
  auth_response_uri: 'https://app.example.com/callback?code=12345&state=abc123'
}

# 5. Exchange the authorization response for a token
token = scheme.exchange_auth_response(credential, auth_response)
```

## Security Considerations

- The `auth_request_id` should be cryptographically secure to prevent request forgery
- State parameters in `callback_params` should be validated on callback to prevent CSRF attacks
- The `auth_uri` should always use HTTPS to protect the authentication process

## See Also

- [Adk::Auth::Scheme](./scheme.md)
- [Adk::Auth::Schemes::OAuth2](./schemes/oauth2.md)
- [Adk::Auth::Schemes::OpenIDConnect](./schemes/oidc.md)
- [Adk::Auth::ExchangedCredential](./exchanged_credential.md) 