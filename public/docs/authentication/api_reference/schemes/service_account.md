# Adk::Auth::Schemes::ServiceAccount

The `ServiceAccount` class implements service account authentication, which allows applications to authenticate with APIs using key-based credentials rather than user credentials. This authentication scheme is designed for server-to-server and automated workflows where no user interaction is required.

## Overview

Service account authentication uses cryptographic key pairs (usually RSA) to sign authentication tokens that are then exchanged for access tokens. The service account scheme in ADK Ruby provides a flexible foundation for implementing various service account authentication methods, with provider-specific implementations available for common cloud services.

## Class Methods

### `new`

Creates a new service account authentication scheme.

**Parameters:**
- `token_url` (String, optional): The token endpoint URL where the service account credentials are exchanged for tokens
- `audience` (String, optional): The target audience for the service account tokens
- `scopes` (Array<String>, optional): The scopes to request for the service account
- `token_lifetime` (Integer, optional): The lifetime of the token in seconds (default: 3600)
- `kwargs` (Hash, optional): Additional parameters for the authentication scheme

**Examples:**

```ruby
# Create a basic service account scheme
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com',
  scopes: ['https://api.example.com/auth/read', 'https://api.example.com/auth/write']
)

# With custom token lifetime
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com',
  token_lifetime: 1800  # 30 minutes
)
```

## Instance Methods

### `type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:service_account`

**Examples:**

```ruby
scheme = Adk::Auth::Schemes::ServiceAccount.new
scheme.type  # => :service_account
```

### `validate_credential`

Validates that a credential is compatible with this scheme.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential to validate

**Returns:**
- Boolean: `true` if the credential is valid for this scheme

**Raises:**
- `Adk::Auth::AuthenticationError`: If the credential is invalid for this scheme

**Examples:**

```ruby
# Create a valid service account credential
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('service-account-key.json'))
)

# Validate the credential
scheme = Adk::Auth::Schemes::ServiceAccount.new
scheme.validate_credential(credential)  # => true
```

### `authenticate`

Authenticates a request using a service account token.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential containing the service account information
- `params` (Hash, optional): Additional parameters for the authentication process
  - `headers` (Hash, optional): HTTP headers to modify
  - `request` (Object, optional): The request object to authenticate

**Returns:**
- Hash: The authenticated request with access token in the Authorization header

**Examples:**

```ruby
# Create a service account credential
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('service-account-key.json'))
)

# Authenticate a request
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com'
)
result = scheme.authenticate(credential, headers: {})

# The result contains the updated headers with the access token
puts result[:headers]['Authorization']  # => "Bearer [access-token]"
```

### `exchange_token`

Exchanges a service account credential for an access token by creating and signing a JWT and exchanging it with the token endpoint.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential containing the service account information
- `params` (Hash, optional): Additional parameters for the token exchange

**Returns:**
- Adk::Auth::ExchangedCredential: The exchanged token

**Examples:**

```ruby
# Create a service account credential
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('service-account-key.json'))
)

# Exchange for a token
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com',
  scopes: ['read', 'write']
)
token = scheme.exchange_token(credential)

# The token contains the access token
puts token[:access_token]  # => "[service-account-access-token]"
puts token.expires_at     # => Time object representing token expiration
```

### `refresh_token`

Refreshes an expired service account token by performing a new token exchange.

**Parameters:**
- `credential` (Adk::Auth::Credential): The original credential
- `token` (Adk::Auth::ExchangedCredential): The token to refresh

**Returns:**
- Adk::Auth::ExchangedCredential: The refreshed token

**Examples:**

```ruby
# Create a service account credential
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('service-account-key.json'))
)

# Exchange for a token
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com'
)
token = scheme.exchange_token(credential)

# Later, refresh the token
refreshed_token = scheme.refresh_token(credential, token)
```

### `create_jwt`

Creates a signed JWT assertion for the service account.

**Parameters:**
- `credential` (Adk::Auth::Credential): The credential containing the service account information
- `params` (Hash, optional): Additional parameters for the JWT

**Returns:**
- String: The signed JWT assertion

**Examples:**

```ruby
# Create a service account credential
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('service-account-key.json'))
)

# Create a JWT
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  audience: 'https://api.example.com',
  scopes: ['read', 'write']
)
jwt = scheme.create_jwt(credential)

# Use the JWT directly for some APIs
puts jwt  # => "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Usage Examples

### Basic Authentication Flow

```ruby
# Create a Service Account scheme
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com',
  scopes: ['read', 'write']
)

# Create a credential from a service account key file
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('service-account-key.json'))
)

# Exchange the credential for a token
token = scheme.exchange_token(credential)

# Use the token to authenticate a request
headers = {}
authenticated = scheme.authenticate(credential, headers: headers)

# The authenticated headers contain the Authorization header with the token
puts authenticated[:headers]['Authorization']  # => "Bearer [access-token]"
```

### With Token Manager

```ruby
# Create a Service Account scheme
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com'
)

# Create a credential from a service account key file
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('service-account-key.json'))
)

# Use with token manager for automatic token management
token_store = Adk::Auth::TokenStore.new(session)
token_manager = Adk::Auth::TokenManager.new(token_store)

# Get a token (this will create, store, and refresh the token as needed)
token = token_manager.get_token(scheme, credential)
```

### With Tool Configuration

```ruby
# Create a Service Account scheme
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://provider.com/oauth2/token',
  audience: 'https://api.example.com'
)

# Create a credential from environment variable
require 'json'
service_account_json = JSON.parse(ENV['SERVICE_ACCOUNT_JSON'])

credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: service_account_json
)

# Configure a tool with the scheme and credential
tool = Adk::Tools::ApiTool.new(
  auth_scheme: scheme,
  auth_credential: credential
)

# Use the tool - authentication happens automatically
result = tool.execute(params)
```

### Using Key File from Path

```ruby
# Create a credential using a key file path
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key_file: 'path/to/service-account-key.json'
)

# Create the scheme and use as normal
scheme = Adk::Auth::Schemes::ServiceAccount.new(
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
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/service-account%40project-id.iam.gserviceaccount.com"
}
```

The exact format may vary by service provider.

## Provider-Specific Implementations

The `ServiceAccount` class serves as a base class for provider-specific implementations:

### Google Service Account

```ruby
# Google-specific implementation has additional optimizations
google_scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)
```

### Custom Service Provider

```ruby
# For a custom service provider
custom_scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://auth.custom-provider.com/token',
  audience: 'https://api.custom-provider.com',
  scopes: ['api:read', 'api:write'],
  additional_claims: {
    'org_id': 'org-123456',
    'tenant': 'tenant-abc'
  }
)
```

## JWT Customization

You can customize the JWT claims when creating the authentication token:

```ruby
# Create a custom JWT with additional claims
custom_jwt = scheme.create_jwt(credential, {
  additional_claims: {
    'sub': 'custom-subject',
    'org_id': 'org-123456',
    'customClaim': 'custom-value'
  },
  expires_in: 1800,  # 30 minutes
  issued_at: Time.now - 60  # Backdated by 1 minute for clock skew
})
```

## Security Considerations

- Store service account keys securely and restrict access
- Grant service accounts the minimum necessary permissions (principle of least privilege)
- Regularly rotate service account keys
- Monitor service account usage for suspicious activity
- Avoid embedding service account keys in client-side code
- Use environment variables or secure credential stores to manage service account keys
- Always use HTTPS for transmitting service account tokens
- Consider using shorter token lifetimes in high-security environments

## Advantages and Limitations

### Advantages
- No user interaction required, suitable for automated processes
- Long-lived credentials with auto-refreshing tokens
- Granular permission control based on service account identity
- Strong cryptographic security

### Limitations
- Key management responsibility shifts to application developers
- Risk of key exposure if not handled properly
- More complex to set up than simple API key authentication
- Provider-specific implementations may have different requirements

## See Also

- [Adk::Auth::Schemes::GoogleServiceAccount](./google_service_account.md)
- [Adk::Auth::Credential](../credential.md)
- [Adk::Auth::ExchangedCredential](../exchanged_credential.md)
- [Adk::Auth::Scheme](../scheme.md)
- [Adk::Auth::TokenManager](../token_manager.md)
- [Service Account Authentication Guide](../../guides/service_account.md) 