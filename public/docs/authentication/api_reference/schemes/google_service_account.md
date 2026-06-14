# Legate::Auth::Schemes::GoogleServiceAccount

The `GoogleServiceAccount` class implements Google-specific service account authentication. It extends the base `ServiceAccount` class with Google Cloud-specific functionality for authenticating with Google APIs.

## Overview

Google Service Account authentication uses a key-based approach where a signed JWT (JSON Web Token) is exchanged for an access token from Google's authentication servers. This scheme is specifically optimized for Google Cloud APIs, handling the proper audience, token URLs, and other Google-specific configuration details.

## Class Methods

### `new`

Creates a new Google Service Account authentication scheme.

**Parameters:**
- `scopes` (Array<String>, optional): The Google API scopes to request access for
- `kwargs` (Hash, optional): Additional parameters for the authentication scheme (inherits ServiceAccount params)

**Examples:**

```ruby
# Basic Google Service Account scheme with scopes
scheme = Legate::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# With additional options
scheme = Legate::Auth::Schemes::GoogleServiceAccount.new(
  scopes: [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/bigquery'
  ],
  token_lifetime: 3600
)
```

## Instance Methods

### `scheme_type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:google_service_account`

**Examples:**

```ruby
scheme = Legate::Auth::Schemes::GoogleServiceAccount.new
scheme.scheme_type  # => :google_service_account
```

### `validate!`

Validates the scheme configuration for Google service account authentication.

**Raises:**
- `Legate::Auth::SchemeValidationError`: If the scheme configuration is invalid

### `apply_to_request`

Applies Google service account authentication to a request by adding the access token to the Authorization header.

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

### `exchange_token`

Exchanges a Google service account credential for an access token by creating and signing a JWT and exchanging it with Google's token endpoint.

**Parameters:**
- `credential` (Legate::Auth::Credential): The credential containing the service account information

**Returns:**
- Legate::Auth::ExchangedCredential: The exchanged token

**Examples:**

```ruby
# Create a service account credential
credential = Legate::Auth::Credential.new(
  auth_type: :google_service_account,
  service_account_key: File.read('google-service-account.json')  # raw JSON string, not a parsed Hash
)

# Exchange for a token
scheme = Legate::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)
token = scheme.exchange_token(credential)

puts token[:access_token]  # => "[google-access-token]"
```

### `refresh_token`

Refreshes an expired Google service account token by performing a new token exchange.

**Parameters:**
- `token` (Legate::Auth::ExchangedCredential): The token to refresh
- `credential` (Legate::Auth::Credential): The original credential

**Returns:**
- Legate::Auth::ExchangedCredential: The refreshed token

**Examples:**

```ruby
refreshed_token = scheme.refresh_token(expired_token, credential)
```

## Usage Examples

### Basic Authentication Flow

```ruby
# Create a Google Service Account scheme
scheme = Legate::Auth::Schemes::GoogleServiceAccount.new(
  scopes: [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/bigquery'
  ]
)

# Create a credential from a service account key file
credential = Legate::Auth::Credential.new(
  auth_type: :google_service_account,
  service_account_key: File.read('google-service-account.json')  # raw JSON string, not a parsed Hash
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
# Create a Google Service Account scheme
scheme = Legate::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# Create a credential from a service account key file
credential = Legate::Auth::Credential.new(
  auth_type: :google_service_account,
  service_account_key: File.read('google-service-account.json')  # raw JSON string, not a parsed Hash
)

# Use with token manager for automatic token management
token_store = Legate::Auth::TokenStore.new(session_service)
token_manager = Legate::Auth::TokenManager.new(token_store)

# Get a token (this will create, store, and refresh the token as needed)
token = token_manager.get_token(scheme, credential)
```

### Using a Key File from Path

```ruby
# Point the credential at a service account key file on disk
credential = Legate::Auth::Credential.new(
  auth_type: :google_service_account,
  service_account_key_file: '/path/to/google-service-account.json'
)

# Create the scheme and use as normal
scheme = Legate::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# Exchange for a token
token = scheme.exchange_token(credential)
```

> **Note:** Application Default Credentials (ADC) are not supported. Provide credentials explicitly via `service_account_key` (a raw JSON string) or `service_account_key_file` (a path).

## Google API Scopes

Common Google API scopes include:

| API | Scope |
|-----|-------|
| Google Cloud Platform (all services) | `https://www.googleapis.com/auth/cloud-platform` |
| BigQuery | `https://www.googleapis.com/auth/bigquery` |
| Cloud Storage | `https://www.googleapis.com/auth/devstorage.read_write` |
| Compute Engine | `https://www.googleapis.com/auth/compute` |
| Google Drive | `https://www.googleapis.com/auth/drive` |
| Gmail | `https://www.googleapis.com/auth/gmail.send` |
| Google Sheets | `https://www.googleapis.com/auth/spreadsheets` |

## Security Considerations

- Store service account keys securely and restrict access
- Grant service accounts the minimum necessary permissions
- Regularly rotate service account keys (Google recommends every 90 days)
- Monitor service account usage for suspicious activity
- Consider using IAM Conditions to restrict service account usage based on source IP, time, etc.

## See Also

- [Legate::Auth::Schemes::ServiceAccount](./service_account)
- [Legate::Auth::Credential](../credential)
- [Legate::Auth::ExchangedCredential](../exchanged_credential)
- [Legate::Auth::TokenManager](../token_manager)
