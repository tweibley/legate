# Service Account Authentication

Service accounts provide a way to authenticate applications without user interaction, typically for server-to-server communication. The ADK Ruby library supports service account authentication with various cloud providers.

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
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://oauth2.googleapis.com/token',
  audience: 'https://oauth2.googleapis.com/token',
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# With additional options
scheme = Adk::Auth::Schemes::ServiceAccount.new(
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
# Using a JSON key file
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('service-account-key.json'))
)
```

#### From Environment Variable

```ruby
# Store the entire JSON key contents in an environment variable
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: ENV['SERVICE_ACCOUNT_JSON']
)
```

#### With Direct Key Information

```ruby
# Provide the key details directly
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  client_email: 'service-account@project-id.iam.gserviceaccount.com',
  private_key: "-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n",
  private_key_id: 'abcdef1234567890'
)
```

## Authentication Flow

Service account authentication is non-interactive and happens automatically when the tool is executed:

```ruby
# 1. Configure the service account scheme
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://oauth2.googleapis.com/token',
  audience: 'https://oauth2.googleapis.com/token',
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
)

# 2. Configure the credential with the service account key
credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('service-account-key.json'))
)

# 3. Configure a tool with the scheme and credential
tool = Adk::Tools::GoogleCloudTool.new(
  auth_scheme: scheme,
  auth_credential: credential
)

# 4. Use the tool - authentication happens automatically
result = tool.execute(params)
```

## Provider-Specific Configurations

### Google Cloud Service Account

```ruby
# Using the GoogleServiceAccount scheme (recommended for Google Cloud)
scheme = Adk::Auth::Schemes::GoogleServiceAccount.new(
  scopes: [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/bigquery'
  ]
)

credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('google-service-account.json'))
)
```

### AWS Service Account

```ruby
# AWS STS token exchange
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://sts.amazonaws.com',
  audience: 'aws.amazonaws.com'
)

credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  service_account_json: JSON.parse(File.read('aws-credentials.json'))
)
```

### Azure Service Account

```ruby
# Azure service principal
scheme = Adk::Auth::Schemes::ServiceAccount.new(
  token_url: 'https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token',
  audience: 'https://management.azure.com/'
)

credential = Adk::Auth::Credential.new(
  auth_type: :service_account,
  client_id: ENV['AZURE_CLIENT_ID'],
  client_secret: ENV['AZURE_CLIENT_SECRET'],
  tenant_id: ENV['AZURE_TENANT_ID']
)
```

## Token Management

Service account tokens are automatically managed by the ADK Ruby library:

- **Token Acquisition**: The JWT assertion is exchanged for an access token
- **Token Storage**: The access token is securely stored in the session state
- **Token Refresh**: When a token expires, a new token is automatically acquired
- **Token Revocation**: Tokens can be revoked when no longer needed

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
   - Always use HTTPS for token exchange
   - Encrypt tokens in transit and at rest

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