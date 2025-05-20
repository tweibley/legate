# Troubleshooting OAuth2 Authentication Issues

This guide addresses common issues encountered when implementing OAuth2 authentication in the ADK Ruby library.

## Common Issues and Solutions

### Authorization Flow Not Starting

**Symptoms:**
- No authentication URL is generated
- No Fiber yield occurs
- Authentication flow doesn't start

**Possible Causes and Solutions:**

1. **Incorrect Scheme Type**
   ```ruby
   # Incorrect: Using the wrong scheme type
   scheme = Adk::Auth::Schemes::APIKey.new
   
   # Correct: Use the OAuth2 scheme
   scheme = Adk::Auth::Schemes::OAuth2.new(
     authorization_url: 'https://provider.com/authorize',
     token_url: 'https://provider.com/token',
     scopes: ['profile', 'email']
   )
   ```

2. **Missing Required Parameters**
   ```ruby
   # Incorrect: Missing required parameters
   scheme = Adk::Auth::Schemes::OAuth2.new
   
   # Correct: Include all required parameters
   scheme = Adk::Auth::Schemes::OAuth2.new(
     authorization_url: 'https://provider.com/authorize',
     token_url: 'https://provider.com/token',
     scopes: ['profile', 'email']
   )
   ```

3. **Incorrect Credential Configuration**
   ```ruby
   # Incorrect: Wrong auth_type or missing client_id
   credential = Adk::Auth::Credential.new(
     auth_type: :api_key,  # Wrong auth_type
     api_key: 'secret'
   )
   
   # Correct: Proper OAuth2 credential
   credential = Adk::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: ENV['CLIENT_ID'],
     client_secret: ENV['CLIENT_SECRET']
   )
   ```

### Token Exchange Failures

**Symptoms:**
- Authorization succeeds but token exchange fails
- Error messages about invalid grant or client authentication

**Possible Causes and Solutions:**

1. **Invalid Redirect URI**
   ```ruby
   # Ensure the redirect URI exactly matches what's registered with the provider
   # The redirect URI in your application must EXACTLY match the one registered
   ```

2. **Client Authentication Issues**
   ```ruby
   # Check if client_secret is correct and properly configured
   credential = Adk::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: ENV['CLIENT_ID'],
     client_secret: ENV['CLIENT_SECRET']  # Verify this is correct
   )
   ```

3. **Authorization Code Expired**
   ```ruby
   # Authorization codes usually expire quickly (30-60 seconds)
   # Ensure your application exchanges the code for a token immediately
   ```

4. **PKCE Issues**
   ```ruby
   # If using PKCE, verify the code_verifier matches what was used for code_challenge
   scheme = Adk::Auth::Schemes::OAuth2.new(
     authorization_url: 'https://provider.com/authorize',
     token_url: 'https://provider.com/token',
     scopes: ['profile', 'email'],
     pkce: true  # Using PKCE
   )
   ```

### Token Refresh Issues

**Symptoms:**
- Access token expires and refresh fails
- "Invalid refresh token" errors

**Possible Causes and Solutions:**

1. **Expired Refresh Token**
   ```ruby
   # Refresh tokens may have limited lifetimes
   # If expired, you need to restart the full authorization flow
   ```

2. **Revoked Refresh Token**
   ```ruby
   # Providers may revoke refresh tokens if:
   # - Too many refresh attempts occur
   # - User revokes app access
   # - Security policies trigger revocation
   ```

3. **Incorrect Token Storage**
   ```ruby
   # Ensure tokens are securely stored with encryption
   # ADK handles this automatically when using the session state
   ```

### Scope-Related Issues

**Symptoms:**
- Authentication succeeds but API access fails with permission errors
- Provider returns scope-related errors

**Possible Causes and Solutions:**

1. **Missing Required Scopes**
   ```ruby
   # Incorrect: Missing necessary scopes
   scheme = Adk::Auth::Schemes::OAuth2.new(
     authorization_url: 'https://provider.com/authorize',
     token_url: 'https://provider.com/token',
     scopes: ['profile']  # Missing needed scopes
   )
   
   # Correct: Include all required scopes
   scheme = Adk::Auth::Schemes::OAuth2.new(
     authorization_url: 'https://provider.com/authorize',
     token_url: 'https://provider.com/token',
     scopes: ['profile', 'email', 'data:read', 'data:write']
   )
   ```

2. **Scope Approval Issues**
   ```ruby
   # If the user didn't approve all requested scopes:
   # 1. Check the exchanged token's scope field
   # 2. Request only essential scopes
   # 3. Handle graceful degradation if some scopes are denied
   ```

## Provider-Specific Issues

### Google OAuth2

- **Invalid Client Error**: Ensure the client ID and redirect URI match exactly what's in the Google Developer Console
- **Consent Screen Required**: Verify you've configured the OAuth consent screen in the Developer Console
- **Domain Verification**: For some scopes, domain verification may be required

### GitHub OAuth2

- **Application Suspended**: GitHub may suspend OAuth apps that exceed rate limits or violate terms
- **User-to-Server vs. Server-to-Server**: Different authentication flows for different access types

### Microsoft/Azure OAuth2

- **Tenant Configuration**: Ensure proper tenant ID configuration
- **Admin Consent Required**: Some scopes require admin consent in organizational contexts

## Debugging Techniques

### Enable Detailed Logging

```ruby
# Enable detailed authentication logging
ADK.configure do |config|
  config.log_level = :debug
end
```

### Inspect Token Response

```ruby
# Add a callback to inspect token responses
ADK::Auth.on_token_exchange do |token_response, error|
  puts "Token response: #{token_response.inspect}"
  puts "Error: #{error.inspect}" if error
end
```

### Test with Mock Provider

```ruby
# Use the mock OAuth2 provider for testing
require 'adk/auth/mock/oauth2_provider'

# Configure the mock provider
mock_provider = ADK::Auth::Mock::OAuth2Provider.new(
  auto_approve: true,
  predefined_tokens: {
    access_token: 'mock-access-token',
    refresh_token: 'mock-refresh-token',
    expires_in: 3600
  }
)

# Use the mock provider URLs
scheme = Adk::Auth::Schemes::OAuth2.new(
  authorization_url: mock_provider.authorization_url,
  token_url: mock_provider.token_url,
  scopes: ['profile', 'email']
)
```

## Next Steps

If you're still experiencing issues after trying these solutions:

1. Check the [OAuth2 Specification](https://oauth.net/2/) for details on the standard
2. Review your provider's specific OAuth2 documentation
3. Check the ADK Ruby [GitHub Issues](https://github.com/yourusername/adk-ruby/issues) for similar problems
4. File a detailed bug report with full logs and reproduction steps 