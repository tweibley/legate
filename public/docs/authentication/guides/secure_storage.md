# Secure Credential Storage

## Overview

Secure storage of authentication credentials and tokens is critical for maintaining the security of your Legate Ruby applications. This guide explains best practices for storing and handling sensitive authentication data.

## Security Considerations

When working with authentication, you need to protect several types of sensitive information:

- **API Keys**: Direct access tokens that grant API access
- **Client Secrets**: OAuth2/OIDC secrets used to authenticate your application
- **Bearer Tokens**: Tokens that provide access to protected resources
- **Access Tokens**: Short-lived tokens obtained through authentication flows
- **Refresh Tokens**: Long-lived tokens used to obtain new access tokens
- **Service Account Keys**: JSON credentials that authenticate as a service account

## Legate Security Architecture

The Legate Ruby library provides several measures to help protect sensitive authentication data:

1. **Optional Encryption**: An opt-in `Legate::Auth::Encryption` module is available for encrypting data at rest
2. **Scoped Storage**: Tokens are cached in scoped session state via the token store
3. **Environment Variables**: Credential values can be sourced from environment variables (the `ENV:` prefix)
4. **Minimal Exposure**: Access tokens are short-lived and refreshed automatically by the `TokenManager`

## Encryption in Legate

> **Important:** Encryption is **opt-in** and is **not** wired into `TokenStore`. `TokenStore#store` persists plaintext token data (`token.to_h`) in scoped state. To encrypt at rest, call the `Legate::Auth::Encryption` module yourself.

The `Legate::Auth::Encryption` module uses the `rbnacl` gem (libsodium SecretBox) for authenticated encryption. `rbnacl` is an optional dependency: the module lazily requires it and raises `LoadError` if it (or libsodium) is missing.

### Using the Encryption Module

`Encryption` is a module (not instantiable). Call its module methods directly. Keys are Base64-encoded; with no key argument it reads `LEGATE_AUTH_ENCRYPTION_KEY`.

```ruby
require 'legate/auth/encryption'

# Generate a Base64 key once and store it securely
key = Legate::Auth::Encryption.generate_key

# Encrypt / decrypt (output is "LGTAUTH" + Base64)
ciphertext = Legate::Auth::Encryption.encrypt(JSON.dump(token.to_h), key)
plaintext  = Legate::Auth::Encryption.decrypt(ciphertext, key)
```

### Applying Encryption to Stored Tokens

Because `TokenStore` does not encrypt, apply encryption in your own storage layer:

```ruby
key = ENV['LEGATE_AUTH_ENCRYPTION_KEY']

# Encrypt before persisting through storage you control
ciphertext = Legate::Auth::Encryption.encrypt(JSON.dump(token.to_h), key)

# Decrypt on read, then rebuild the token
data = JSON.parse(Legate::Auth::Encryption.decrypt(ciphertext, key), symbolize_names: true)
token = Legate::Auth::ExchangedCredential.from_h(data)
```

## Environment Variable Handling

The Legate Ruby library supports sourcing credential values from environment variables, which is a security best practice.

### Direct Environment Variable Usage

```ruby
# Read environment variables at construction time
api_key_credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: ENV['API_KEY']
)

oauth2_credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['OAUTH2_CLIENT_ID'],
  client_secret: ENV['OAUTH2_CLIENT_SECRET']
)
```

### Environment Variable References

The only reference mechanism is the `ENV:` prefix inside a string value
(resolved lazily when the attribute is read). There are no `*_env` attributes.

```ruby
api_key_credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: 'ENV:API_KEY'
)

oauth2_credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'ENV:OAUTH2_CLIENT_ID',
  client_secret: 'ENV:OAUTH2_CLIENT_SECRET'
)
```

## Secure Token Storage

The Legate Ruby library provides the `TokenStore` class for secure storage of authentication tokens.

### Creating a Token Store

```ruby
# Create a token store with the session service (positional argument)
token_store = Legate::Auth::TokenStore.new(session_service)
```

### Storing Tokens

`store(key, token)` accepts a string key and an `ExchangedCredential` (it
serializes `token.to_h` into scoped state; it does not encrypt):

```ruby
token = Legate::Auth::ExchangedCredential.new(
  auth_type: :oauth2,
  access_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
  refresh_token: 'rtok_abc123...',
  expires_in: 3600
)

token_store.store('client123', token)
```

### Retrieving Tokens

```ruby
# Returns an ExchangedCredential, or nil if missing/expired
token = token_store.get('client123')
```

## Service Account Key Security

Service account keys (especially Google Service Account JSON keys) require special security consideration.

### Store Service Account Keys Securely

```ruby
# Option 1: Store the JSON in an environment variable (recommended).
# service_account_key takes the raw JSON string.
ENV['GOOGLE_SERVICE_ACCOUNT_JSON'] = '{"type":"service_account","project_id":"..."}'

credential = Legate::Auth::Credential.new(
  auth_type: :google_service_account,
  service_account_key: ENV['GOOGLE_SERVICE_ACCOUNT_JSON']
)

# Option 2: Reference the env var lazily with the ENV: prefix
credential = Legate::Auth::Credential.new(
  auth_type: :google_service_account,
  service_account_key: 'ENV:GOOGLE_SERVICE_ACCOUNT_JSON'
)

# Option 3: Reference a file path with service_account_key_file
credential = Legate::Auth::Credential.new(
  auth_type: :google_service_account,
  service_account_key_file: '/secure/path/to/service-account.json'
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
  name: legate-app
spec:
  template:
    spec:
      containers:
      - name: legate-app
        image: legate-app:latest
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
oauth2_credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['OAUTH2_CLIENT_ID'],
  client_secret: ENV['OAUTH2_CLIENT_SECRET']
)
```

## Session Service Security

The Legate session service stores authentication tokens in memory as plaintext (unless you apply opt-in encryption yourself). Ensure proper security:

1. **Use HTTPS**: Ensure all communication is over HTTPS
2. **Session isolation**: Use proper session management practices
3. **Process lifecycle**: Be aware that in-memory sessions are lost on process restart

```ruby
# Create the in-memory session service
session_service = Legate::SessionService::InMemory.new
```

## Security Checklist

Use this checklist to ensure you're following security best practices:

- [ ] Store credentials in environment variables, not in code
- [ ] Use HTTPS for all API and authentication endpoints
- [ ] Configure proper token expiration and refresh thresholds
- [ ] Implement proper error handling for authentication failures
- [ ] Ensure session service is properly configured
- [ ] Rotate credentials regularly
- [ ] Use the principle of least privilege for service accounts
- [ ] Implement proper logging for authentication events (but don't log sensitive data)
- [ ] Keep the Legate Ruby library updated to get security fixes

## Related Topics
- [Authentication Configuration](./configuration)
- [Token Lifecycle Management](./token_lifecycle)
- [OAuth2 Authentication](./oauth2)
- [Service Account Authentication](./service_account)
- [`Legate::Auth::TokenStore` API Reference](../api_reference/token_store)
- [`Legate::Auth::Encryption` API Reference](../api_reference/encryption) 