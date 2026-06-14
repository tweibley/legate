# Legate::Auth::Schemes::ServiceAccount

The `ServiceAccount` class implements service account authentication, which allows applications to authenticate with APIs using key-based credentials rather than user credentials. This authentication scheme is designed for server-to-server and automated workflows where no user interaction is required.

## Overview

Service account authentication uses cryptographic key pairs (usually RSA) to sign authentication tokens that are then exchanged for access tokens. The service account scheme in Legate Ruby provides a flexible foundation for implementing various service account authentication methods, with provider-specific implementations available for common cloud services.

## Class Methods

### `new`

Creates a new service account authentication scheme.

**Parameters:**
- `token_url` (String, optional keyword): The token endpoint URL where the service account credentials are exchanged for tokens
- `audience` (String, optional keyword): The target audience for the service account tokens
- `scopes` (Array<String>, optional keyword): The scopes to request for the service account
- `token_lifetime` (Integer, optional keyword): The lifetime of the token in seconds (default: 3600)
- `client_email` (String, optional keyword): The service account client email
- `private_key` (String, optional keyword): The private key for signing JWTs
- `private_key_id` (String, optional keyword): The private key ID
- `config` (Hash, optional keyword): Additional configuration (default: {})

**Examples:**

```ruby
# Create a basic service account scheme
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com',
  scopes: ['https://api.example.com/auth/read', 'https://api.example.com/auth/write']
)

# With custom token lifetime
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com',
  token_lifetime: 1800  # 30 minutes
)
```

## Instance Methods

### `scheme_type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:service_account`

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::ServiceAccount.new
scheme.scheme_type  # => :service_account
```

### `validate!`

Validates the scheme configuration.

**Raises:**
- `Legate::Auth::SchemeValidationError`: If the scheme configuration is invalid

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token'
)
scheme.validate!
```

### `apply_to_request`

Applies service account authentication to a request by adding the access token to the Authorization header.

**Parameters:**
- `request` (Hash): The request to authenticate
- `credential` (Legate::Auth::ExchangedCredential): The exchanged credential containing the access token

**Returns:**
- Hash: The authenticated request with access token in the Authorization header

**Examples:**

```ruby
request = { headers: {} }
authenticated = scheme.apply_to_request(request, exchanged_credential)
puts authenticated[:headers]['Authorization']  # => "Bearer [access-token]"
```

### `fetch_token`

Fetches a token from the token endpoint using a signed JWT.

**Parameters:**
- `credential` (Legate::Auth::Credential): The credential containing the service account information

**Returns:**
- Legate::Auth::ExchangedCredential: The fetched token

### `exchange_token`

Exchanges a service account credential for an access token by creating and signing a JWT and exchanging it with the token endpoint.

**Parameters:**
- `credential` (Legate::Auth::Credential): The credential containing the service account information

**Returns:**
- Legate::Auth::ExchangedCredential: The exchanged token

**Examples:**

```ruby
# Create a service account credential
credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: File.read('service-account-key.json')  # raw JSON string, not a parsed Hash
)

# Exchange for a token
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com',
  scopes: ['read', 'write']
)
token = scheme.exchange_token(credential)

puts token[:access_token]  # => "[service-account-access-token]"
```

### `supports_refresh?`

Returns `true` -- service account schemes always support token refresh by re-exchanging credentials.

**Returns:**
- Boolean: `true`

### `refresh_token`

Refreshes an expired service account token by performing a new token exchange.

**Parameters:**
- `token` (Legate::Auth::ExchangedCredential): The token to refresh
- `credential` (Legate::Auth::Credential): The original credential

**Returns:**
- Legate::Auth::ExchangedCredential: The refreshed token

**Examples:**

```ruby
refreshed_token = scheme.refresh_token(expired_token, credential)
```

### `create_signed_jwt`

Creates a signed JWT assertion for the service account.

**Parameters:**
- `service_account_key` (Hash, optional): The service account key to use for signing (default: nil, uses configured key)

**Returns:**
- String: The signed JWT assertion

**Examples:**

```ruby
jwt = scheme.create_signed_jwt
puts jwt  # => "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### `to_h`

Converts the scheme to a hash representation.

**Returns:**
- Hash: A hash representation of the scheme configuration

## Usage Examples

### Basic Authentication Flow

```ruby
# Create a Service Account scheme
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com',
  scopes: ['read', 'write']
)

# Create a credential from a service account key file
credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: File.read('service-account-key.json')  # raw JSON string, not a parsed Hash
)

# Exchange the credential for a token
token = scheme.exchange_token(credential)

# Apply to a request
request = { headers: {} }
authenticated = scheme.apply_to_request(request, token)
puts authenticated[:headers]['Authorization']  # => "Bearer [access-token]"
```

### With Token Manager

```ruby
# Create a Service Account scheme
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com'
)

# Create a credential from a service account key file
credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: File.read('service-account-key.json')  # raw JSON string, not a parsed Hash
)

# Use with token manager for automatic token management
token_store = Legate::Auth::TokenStore.new(session_service)
token_manager = Legate::Auth::TokenManager.new(token_store)

# Get a token (this will create, store, and refresh the token as needed)
token = token_manager.get_token(scheme, credential)
```

### Using Key File from Path

```ruby
# Create a credential using a key file path
credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key_file: 'path/to/service-account-key.json'
)

# Create the scheme and use as normal
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com'
)

# Exchange for a token
token = scheme.exchange_token(credential)
```

## Service Account Key Format

A standard service account key JSON file typically contains:

```json
{
  "type": "service_account",
  "project_id": "your-project-id",
  "private_key_id": "abcdef1234567890",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n",
  "client_email": "service-account@project-id.iam.gserviceaccount.com",
  "client_id": "123456789012345678901",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
```

The exact format may vary by service provider.

## Security Considerations

- Store service account keys securely and restrict access
- Grant service accounts the minimum necessary permissions (principle of least privilege)
- Regularly rotate service account keys
- Monitor service account usage for suspicious activity
- Avoid embedding service account keys in client-side code
- Use environment variables or secure credential stores to manage service account keys
- Always use HTTPS for transmitting service account tokens
- Consider using shorter token lifetimes in high-security environments

## See Also

- [Legate::Auth::Schemes::GoogleServiceAccount](./google_service_account)
- [Legate::Auth::Credential](../credential)
- [Legate::Auth::ExchangedCredential](../exchanged_credential)
- [Legate::Auth::Scheme](../scheme)
- [Legate::Auth::TokenManager](../token_manager)
