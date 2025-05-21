# Secure Credential Storage

## Overview

Secure storage of authentication credentials and tokens is critical for maintaining the security of your ADK Ruby applications. This guide explains best practices for storing and handling sensitive authentication data.

## Security Considerations

When working with authentication, you need to protect several types of sensitive information:

- **API Keys**: Direct access tokens that grant API access
- **Client Secrets**: OAuth2/OIDC secrets used to authenticate your application
- **Bearer Tokens**: Tokens that provide access to protected resources
- **Access Tokens**: Short-lived tokens obtained through authentication flows
- **Refresh Tokens**: Long-lived tokens used to obtain new access tokens
- **Service Account Keys**: JSON credentials that authenticate as a service account

## ADK Security Architecture

The ADK Ruby library implements several security measures to protect sensitive authentication data:

1. **Encryption**: Sensitive data is encrypted before storage
2. **Secure Storage**: Tokens are stored in a secure token store
3. **Environment Variables**: Credential values can be sourced from environment variables
4. **Minimal Exposure**: Access tokens are short-lived and refreshed automatically

## Encryption in ADK

The ADK Ruby library uses the `rbnacl` gem for authenticated encryption of sensitive authentication data.

### Encryption Architecture

```ruby
module Adk
  module Auth
    class Encryption
      # Initialize with encryption key
      def initialize(key)
        @box = RbNaCl::SimpleBox.from_secret_key(key)
      end
      
      # Encrypt data
      def encrypt(data)
        encrypted_data = @box.encrypt(data.to_json)
        Base64.strict_encode64(encrypted_data)
      end
      
      # Decrypt data
      def decrypt(encrypted_data)
        decoded_data = Base64.strict_decode64(encrypted_data)
        JSON.parse(@box.decrypt(decoded_data))
      end
    end
  end
end
```

### How Encryption Is Used

The ADK `TokenStore` automatically encrypts tokens before storage:

```ruby
# In TokenStore#store
def store(credential_id:, tokens:)
  # Encrypt sensitive token data
  encrypted_tokens = @encryption.encrypt(tokens)
  
  # Store the encrypted tokens
  @state[:auth_tokens] ||= {}
  @state[:auth_tokens][credential_id] = encrypted_tokens
  
  # Persist the updated state
  @session_service.set_state(@state)
  
  tokens
end
```

## Environment Variable Handling

The ADK Ruby library supports sourcing credential values from environment variables, which is a security best practice.

### Direct Environment Variable Usage

```ruby
# Use environment variables directly
api_key_credential = Adk::Auth::Credential.new(
  api_key: ENV['API_KEY']
)

oauth2_credential = Adk::Auth::Credential.new(
  client_id: ENV['OAUTH2_CLIENT_ID'],
  client_secret: ENV['OAUTH2_CLIENT_SECRET']
)
```

### Environment Variable References

```ruby
# Reference environment variables by name
api_key_credential = Adk::Auth::Credential.new(
  api_key_env: 'API_KEY'
)

oauth2_credential = Adk::Auth::Credential.new(
  client_id_env: 'OAUTH2_CLIENT_ID',
  client_secret_env: 'OAUTH2_CLIENT_SECRET'
)
```

## Secure Token Storage

The ADK Ruby library provides the `TokenStore` class for secure storage of authentication tokens.

### Creating a Secure Token Store

```ruby
# Create a token store with the session service
token_store = Adk::Auth::TokenStore.new(
  session_service: session_service
)
```

### Storing Tokens Securely

```ruby
# Store tokens securely
token_store.store(
  credential_id: 'client123',
  tokens: {
    access_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
    refresh_token: 'rtok_abc123...',
    expires_at: Time.now + 3600
  }
)
```

### Retrieving Tokens Securely

```ruby
# Retrieve and decrypt tokens
tokens = token_store.get(credential_id: 'client123')
```

## Service Account Key Security

Service account keys (especially Google Service Account JSON keys) require special security consideration.

### Store Service Account Keys Securely

```ruby
# Option 1: Store in environment variable (recommended)
ENV['GOOGLE_SERVICE_ACCOUNT_JSON'] = '{"type":"service_account","project_id":"..."}'

credential = Adk::Auth::Credential.new(
  service_account_json: ENV['GOOGLE_SERVICE_ACCOUNT_JSON']
)

# Option 2: Reference environment variable by name
credential = Adk::Auth::Credential.new(
  service_account_json_env: 'GOOGLE_SERVICE_ACCOUNT_JSON'
)

# Option 3: Reference file path (less secure)
credential = Adk::Auth::Credential.new(
  service_account_json_path: '/secure/path/to/service-account.json'
)
```

## Deployment Security Best Practices

### Environment Variables in Production

For production environments, consider these best practices for handling environment variables:

1. **Use a secrets manager**: Store secrets in a dedicated secrets manager like HashiCorp Vault, AWS Secrets Manager, or Google Secret Manager
2. **Inject at runtime**: Inject secrets into your application at runtime rather than storing them in configuration files
3. **Use minimal permissions**: For service accounts, use the principle of least privilege
4. **Rotate credentials**: Regularly rotate credentials and tokens

### Example with Docker Compose

```yaml
# docker-compose.yml
version: '3'
services:
  app:
    build: .
    environment:
      - OAUTH2_CLIENT_ID=${OAUTH2_CLIENT_ID}
      - OAUTH2_CLIENT_SECRET=${OAUTH2_CLIENT_SECRET}
      - API_KEY=${API_KEY}
    env_file:
      - .env.production
```

### Example with Kubernetes

```yaml
# deployment.yaml
apiVersion: v1
kind: Secret
metadata:
  name: auth-credentials
type: Opaque
data:
  oauth2-client-id: <base64-encoded-client-id>
  oauth2-client-secret: <base64-encoded-client-secret>
  api-key: <base64-encoded-api-key>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: adk-app
spec:
  template:
    spec:
      containers:
      - name: adk-app
        image: adk-app:latest
        env:
        - name: OAUTH2_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: auth-credentials
              key: oauth2-client-id
        - name: OAUTH2_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: auth-credentials
              key: oauth2-client-secret
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: auth-credentials
              key: api-key
```

## Development Security Best Practices

### Local Environment Variables

For development environments, consider these approaches:

1. **Use a .env file**: Store environment variables in a .env file that is not committed to source control
2. **Use a development-only secrets manager**: Set up a development instance of your secrets manager
3. **Use dummy credentials for development**: Use separate credentials for development environments

### Example .env File

```
# .env (add to .gitignore)
OAUTH2_CLIENT_ID=dev-client-id
OAUTH2_CLIENT_SECRET=dev-client-secret
API_KEY=dev-api-key
GOOGLE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"..."}
```

### Loading Environment Variables

```ruby
# Load environment variables
require 'dotenv'
Dotenv.load

# Use in credential creation
oauth2_credential = Adk::Auth::Credential.new(
  client_id: ENV['OAUTH2_CLIENT_ID'],
  client_secret: ENV['OAUTH2_CLIENT_SECRET']
)
```

## Redis Security for Token Storage

When using Redis for session storage (which stores encrypted tokens), follow these security practices:

1. **Enable Redis authentication**: Set a strong password for Redis
2. **Use TLS**: Enable TLS for Redis connections
3. **Network security**: Restrict access to the Redis server
4. **Set appropriate key expiry**: Configure TTL for session keys

### Secure Redis Configuration

```ruby
# Create a secure Redis session service
session_service = Adk::SessionService::Redis.new(
  redis_url: "rediss://:#{ENV['REDIS_PASSWORD']}@redis.example.com:6379/0",
  namespace: 'adk:sessions',
  ttl: 86400 # 24 hours
)
```

## Session Service Security

The ADK session service stores encrypted authentication tokens. Ensure proper security:

1. **Use Redis in production**: The in-memory session service should only be used for development
2. **Configure appropriate TTL**: Set a reasonable time-to-live for sessions
3. **Use HTTPS**: Ensure all communication is over HTTPS
4. **Session isolation**: Use namespaces to isolate sessions

```ruby
# Create a secure session service with namespace
session_service = Adk::SessionService::Redis.new(
  redis_url: ENV['REDIS_URL'],
  namespace: "adk:sessions:#{ENV['ENVIRONMENT']}",
  ttl: 3600
)
```

## Security Checklist

Use this checklist to ensure you're following security best practices:

- [ ] Store credentials in environment variables, not in code
- [ ] Use HTTPS for all API and authentication endpoints
- [ ] Configure proper token expiration and refresh thresholds
- [ ] Implement proper error handling for authentication failures
- [ ] Use secure Redis configuration for session storage
- [ ] Rotate credentials regularly
- [ ] Use the principle of least privilege for service accounts
- [ ] Implement proper logging for authentication events (but don't log sensitive data)
- [ ] Keep the ADK Ruby library updated to get security fixes

## Related Resources

- [Authentication Configuration](./configuration.md)
- [Token Lifecycle Management](./token_lifecycle.md)
- [OAuth2 Authentication](./oauth2.md)
- [Service Account Authentication](./service_account.md)
- [`Adk::Auth::TokenStore` API Reference](../api_reference/token_store.md)
- [`Adk::Auth::Encryption` API Reference](../api_reference/encryption.md) 