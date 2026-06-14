# Service Account Authentication

Service accounts provide a way to authenticate applications without user interaction, typically for server-to-server communication. The Legate Ruby library supports service account authentication with various cloud providers.

## Overview

Service account authentication uses a key-based approach where:

1. The application creates a signed JWT (JSON Web Token) using the service account's private key
2. This JWT is exchanged for an access token from the authorization server
3. The access token is then used to authenticate API requests

This flow is ideal for:
- Server-to-server integrations
- Background processing
- Automated tasks and scheduled jobs
- Services that run without user interaction

## Configuration

### Creating a Service Account Scheme

```ruby
# Basic service account scheme
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://oauth2.googleapis.com/token',
  audience: 'https://oauth2.googleapis.com/token',
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# With additional options
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://oauth2.googleapis.com/token',
  audience: 'https://oauth2.googleapis.com/token',
  scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  token_lifetime: 3600  # Access token lifetime in seconds (default: 3600)
)
```

### Creating a Service Account Credential

There are several ways to provide the service account key information:

#### From a JSON Key File

```ruby
# Using a JSON key file. service_account_key takes a raw JSON string
# (not a parsed Hash); or use service_account_key_file with a path.
credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: File.read('service-account-key.json')
)

# Or point at the file directly:
credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key_file: '/path/to/service-account-key.json'
)
```

#### From Environment Variable

```ruby
# Store the entire JSON key contents in an environment variable (raw string)
credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: ENV['SERVICE_ACCOUNT_JSON']
)

# Or reference it lazily with the ENV: prefix:
credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: 'ENV:SERVICE_ACCOUNT_JSON'
)
```

## Authentication Flow

Service account authentication is non-interactive and happens automatically when the tool is executed:

```ruby
# 1. Configure the service account scheme
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://oauth2.googleapis.com/token',
  audience: 'https://oauth2.googleapis.com/token',
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# 2. Configure the credential with the service account key (raw JSON string)
credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: File.read('service-account-key.json')
)

# 3. Exchange the credential for an access token
token = scheme.exchange_token(credential)

# 4. Apply the token to outbound requests
connection = Legate::Auth.create_connection('https://api.example.com',
  scheme: scheme,
  credential: token
)
result = connection.get(path: '/resource')
```

## Provider-Specific Configurations

### Google Cloud Service Account

```ruby
# Using the GoogleServiceAccount scheme (recommended for Google Cloud)
scheme = Legate::Auth::Schemes::GoogleServiceAccount.new(
  scopes: [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/bigquery'
  ]
)

credential = Legate::Auth::Credential.new(
  auth_type: :google_service_account,
  service_account_key: File.read('google-service-account.json')
)
```

### AWS Service Account

```ruby
# AWS STS token exchange
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://sts.amazonaws.com',
  audience: 'aws.amazonaws.com'
)

credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: File.read('aws-credentials.json')
)
```

### Azure Service Account

```ruby
# Azure service principal
scheme = Legate::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token',
  audience: 'https://management.azure.com/'
)

credential = Legate::Auth::Credential.new(
  auth_type: :service_account,
  service_account_key: ENV['AZURE_SERVICE_ACCOUNT_JSON']  # raw JSON string
)
```

> The base `ServiceAccount` scheme reads its key material from the credential's
> `service_account_key` (raw JSON string) or `service_account_key_file` (path).
> Provider-specific client_id/secret/tenant fields are not read directly by the
> base scheme.

## Token Management

When used with a `TokenManager`, service account tokens are managed for you:

- **Token Acquisition**: The JWT assertion is exchanged for an access token
- **Token Storage**: The access token is cached in scoped session state (plaintext; apply `Legate::Auth::Encryption` yourself for at-rest encryption)
- **Token Refresh**: Service account schemes support refresh — an expired token triggers a new exchange (`supports_refresh?` is `true`)

## Security Best Practices

1. **Secure Key Storage**:
   - Never commit service account keys to source control
   - Use environment variables or secret management services
   - Restrict file permissions on key files

2. **Principle of Least Privilege**:
   - Create service accounts with minimal required permissions
   - Request only necessary scopes
   - Use different service accounts for different purposes

3. **Key Rotation**:
   - Regularly rotate service account keys
   - Monitor key usage for suspicious activity

4. **Secure Transport**:
   - Always use HTTPS for token exchange (token URLs are SSRF-checked by `Legate::Auth::UrlGuard`)
   - HTTPS encrypts tokens in transit; for at-rest encryption use the opt-in `Legate::Auth::Encryption` module

## Creating Service Account Keys

### Google Cloud

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to IAM & Admin > Service Accounts
3. Select or create a service account
4. Click "Keys" > "Add Key" > "Create new key"
5. Choose JSON format and click "Create"
6. Save the downloaded key file securely

### AWS

1. Go to the [AWS Management Console](https://console.aws.amazon.com/)
2. Navigate to IAM > Users
3. Create a new user or select an existing one
4. Click "Security credentials" > "Create access key"
5. Save the Access Key ID and Secret Access Key securely

### Azure

1. Go to the [Azure Portal](https://portal.azure.com/)
2. Navigate to Azure Active Directory > App registrations
3. Create a new registration or select an existing one
4. Go to "Certificates & secrets" > "New client secret"
5. Create a secret and save the value securely

## Troubleshooting

If you encounter issues with service account authentication:

- Verify that the service account key is valid and correctly formatted
- Check that the service account has the necessary permissions
- Ensure the scopes requested are allowed for the service account
- Verify that the audience value matches what the provider expects
- Check that the token URL is correct for your provider

## Related Topics
- [Token Lifecycle Management](./token_lifecycle) - Advanced token management techniques
- [Secure Credential Storage](./secure_storage) - Best practices for credential security
- [OAuth2 Authentication](./oauth2) - Learn about OAuth2 authentication for user-based flows 