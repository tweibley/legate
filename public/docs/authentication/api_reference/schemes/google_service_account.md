# Adk::Auth::Schemes::GoogleServiceAccount

The `GoogleServiceAccount` class implements Google-specific service account authentication. It extends the base `ServiceAccount` class with Google Cloud-specific functionality for authenticating with Google APIs.

## Overview

Google Service Account authentication uses a key-based approach where a signed JWT (JSON Web Token) is exchanged for an access token from Google's authentication servers. This scheme is specifically optimized for Google Cloud APIs, handling the proper audience, token URLs, and other Google-specific configuration details.

## Class Methods

### `new`

Creates a new Google Service Account authentication scheme.

**Parameters:**
- `scopes` (Array<String>, optional): The Google API scopes to request access for
- `kwargs` (Hash, optional): Additional parameters for the authentication scheme

**Examples:**

```ruby
# Basic Google Service Account scheme with scopes
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# With additional options
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/bigquery'
  ],
  token_lifetime: 3600  # Access token lifetime in seconds (default: 3600)
)
```

## Instance Methods

### `type`

Returns the type of the authentication scheme.

**Returns:**
- Symbol: `:google_service_account`

**Examples:**

```ruby
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new
scheme.type  # => :google_service_account
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
# Create a valid Google service account credential
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('google-service-account.json'))
)

# Validate the credential
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new
scheme.validate_credential(credential)  # => true
```

### `authenticate`

Authenticates a request using a Google service account token.

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
  service_account_json: JSON.parse(File.read('google-service-account.json'))
)

# Authenticate a request
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)
result = scheme.authenticate(credential, headers: {})

# The result contains the updated headers with the access token
puts result[:headers]['Authorization']  # => "Bearer [access-token]"
```

### `exchange_token`

Exchanges a Google service account credential for an access token by creating and signing a JWT and exchanging it with Google's token endpoint.

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
  service_account_json: JSON.parse(File.read('google-service-account.json'))
)

# Exchange for a token
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)
token = scheme.exchange_token(credential)

# The token contains the Google access token
puts token[:access_token]  # => "[google-access-token]"
puts token.expires_at     # => Time object representing token expiration
```

### `refresh_token`

Refreshes an expired Google service account token by performing a new token exchange.

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
  service_account_json: JSON.parse(File.read('google-service-account.json'))
)

# Exchange for a token
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)
token = scheme.exchange_token(credential)

# Later, refresh the token
refreshed_token = scheme.refresh_token(credential, token)
```

## Usage Examples

### Basic Authentication Flow

```ruby
# Create a Google Service Account scheme
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/bigquery'
  ]
)

# Create a credential from a service account key file
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('google-service-account.json'))
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
# Create a Google Service Account scheme
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# Create a credential from a service account key file
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('google-service-account.json'))
)

# Use with token manager for automatic token management
token_store = Adk::Auth::TokenStore.new(session)
token_manager = Adk::Auth::TokenManager.new(token_store)

# Get a token (this will create, store, and refresh the token as needed)
token = token_manager.get_token(scheme, credential)
```

### With Tool Configuration

```ruby
# Create a Google Service Account scheme
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# Create a credential from environment variable
require 'json'
service_account_json = JSON.parse(ENV['GOOGLE_SERVICE_ACCOUNT_JSON'])

credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: service_account_json
)

# Configure a tool with the scheme and credential
tool = Adk::Tools::GoogleCloudTool.new(
  auth_scheme: scheme,
  auth_credential: credential
)

# Use the tool - authentication happens automatically
result = tool.execute(params)
```

### Using Application Default Credentials

```ruby
# The GoogleServiceAccount scheme can use Application Default Credentials
# if they are available in the environment

# Set up the environment variable pointing to your service account key
# export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json

# Create a credential that uses the default credentials
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  use_application_default: true  # Use the credentials from GOOGLE_APPLICATION_CREDENTIALS
)

# Create the scheme and use as normal
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# Exchange for a token
token = scheme.exchange_token(credential)
```

## Service Account Key Format

A Google service account key is a JSON file with the following structure:

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

For a complete list of Google API scopes, see the [Google OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/oauth2/scopes) reference.

## Security Considerations

- Store service account keys securely and restrict access
- Grant service accounts the minimum necessary permissions
- Regularly rotate service account keys (Google recommends every 90 days)
- Monitor service account usage for suspicious activity
- Consider using IAM Conditions to restrict service account usage based on source IP, time, etc.

## See Also

- [Adk::Auth::Schemes::ServiceAccount](./service_account)
- [Adk::Auth::Credential](../credential)
- [Adk::Auth::ExchangedCredential](../exchanged_credential)
- [Adk::Auth::TokenManager](../token_manager)
- [Google Service Account Authentication Guide](../../guides/service_account) 