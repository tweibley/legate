# Legate::Auth::Schemes::OpenIDConnect (OIDC)

The `OpenIDConnect` class implements the OpenID Connect (OIDC) authentication scheme, which provides a layer of identity verification on top of OAuth 2.0 protocols. It handles the secure authentication and authorization flow between your application and OIDC providers.

> **Note**: This class is also available via the `OIDC` alias for backward compatibility. Both `:oidc` and `:openid_connect` scheme types map to this same `OpenIDConnect` class.

For full documentation including all methods, constructor parameters, and advanced usage examples, see the main [OpenIDConnect reference](./openid_connect).

## Quick Start

```ruby
# Create a basic OIDC scheme
scheme = Legate::Auth::Schemes::OpenIDConnect.new(
  discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
  scopes: ['openid', 'email', 'profile']
)

# Set up credential with client details
credential = Legate::Auth::Credential.new(
  auth_type: :oidc,
  client_id: ENV['OIDC_CLIENT_ID'],
  client_secret: ENV['OIDC_CLIENT_SECRET']
)

# Create config and build authorization URI
config = Legate::Auth::Config.new(scheme: scheme, credential: credential)
state = SecureRandom.hex(16)
auth_url = config.build_authorization_uri(
  'http://localhost:3000/auth/callback',
  state
)

# After callback, exchange token
config.response_uri = callback_uri
token = scheme.exchange_token(config, credential)

# Verify ID token
claims = scheme.verify_id_token(token[:id_token])

# Get user info
user_info = scheme.get_userinfo(token[:access_token])
```

## Key Methods

- `scheme_type` - Returns `:openid_connect`
- `validate!` - Validates scheme configuration
- `build_authorization_uri(config, redirect_uri, state)` - Builds the authorization URL
- `apply_to_request(request, credential)` - Applies authentication to a request
- `exchange_token(config, credential)` - Exchanges authorization code for tokens
- `refresh_token(exchanged_credential, credential)` - Refreshes expired tokens
- `verify_id_token(id_token, nonce, audience)` - Verifies an ID token
- `get_userinfo(access_token)` - Gets user info from the userinfo endpoint
- `discover_endpoints` - Discovers OIDC endpoints
- `to_h` - Converts to hash

## Using with Token Manager

```ruby
token_store = Legate::Auth::TokenStore.new(session_service)
token_manager = Legate::Auth::TokenManager.new(token_store)

# Get a token (will auto-refresh if expired)
token = token_manager.get_token(scheme, credential)
```

## See Also

- [Legate::Auth::Schemes::OpenIDConnect (full reference)](./openid_connect)
- [Legate::Auth::Credential](../credential)
- [Legate::Auth::ExchangedCredential](../exchanged_credential)
- [Legate::Auth::Scheme](../scheme)
- [Legate::Auth::TokenManager](../token_manager)
