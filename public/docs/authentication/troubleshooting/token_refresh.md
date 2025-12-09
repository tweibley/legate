# Token Refresh Problems

This guide addresses common issues encountered when refreshing authentication tokens in the ADK Ruby library.

## Common Token Refresh Issues

### Token Expires Too Quickly

**Symptoms:**
- Tokens expire before their expected lifetime
- Frequent re-authentication prompts
- Log messages about token expiration

**Possible Causes and Solutions:**

1. **Clock Skew**
   ```ruby
   # Problem: Your server's clock is out of sync with the provider's clock
   
   # Solution: Sync your server time with NTP
   # On Linux: sudo ntpdate time.google.com
   # On macOS: sudo sntp -sS time.apple.com
   ```

2. **Incorrect Expiration Calculation**
   ```ruby
   # Problem: The token's expires_in value is misinterpreted
   
   # Check how the token's expiration is calculated
   token = Adk::Auth::ExchangedCredential.new(
     auth_type: :oauth2,
     access_token: 'access-token',
     expires_in: 3600  # Seconds from creation time
   )
   
   # Verify the expected expiration time
   puts "Token expires at: #{token.expires_at}"
   ```

3. **Buffer Too Large**
   ```ruby
   # Problem: The refresh buffer is too large, triggering refresh too early
   
   # Solution: Adjust the refresh buffer to a smaller value
   token_manager = Adk::Auth::TokenManager.new(token_store, {
     refresh_buffer: 30  # Seconds (default is 60)
   })
   ```

### Token Refresh Fails

**Symptoms:**
- "Invalid refresh token" errors
- Authentication errors after token expiration
- Failed API calls after some time period

**Possible Causes and Solutions:**

1. **Expired Refresh Token**
   ```ruby
   # Problem: The refresh token itself has expired
   
   # Solution: Request a new refresh token with offline access
   scheme = Adk::Auth::Schemes::OAuth2.new(
     authorization_url: 'https://auth.example.com/authorize',
     token_url: 'https://auth.example.com/token',
     scopes: ['profile', 'email'],
     additional_params: {
       'access_type' => 'offline',  # For Google
       'prompt' => 'consent'        # Force a new refresh token
     }
   )
   ```

2. **Token Revoked by Provider**
   ```ruby
   # Problem: The provider has revoked the refresh token
   
   # Solution: Check token revocation events in the provider's admin console
   # Most providers have an audit log or token management interface
   ```

3. **Connection Issues**
   ```ruby
   # Problem: Network issues prevent reaching the token endpoint
   
   # Solution: Add retry logic
   token_manager = Adk::Auth::TokenManager.new(token_store, {
     retry_max_attempts: 5,   # Increase max retries (default: 3)
     retry_delay: 3,          # Seconds between retries (default: 2)
     retry_backoff: 2.0       # Backoff multiplier (default: 1.5)
   })
   ```

4. **Token Not Stored Correctly**
   ```ruby
   # Problem: The refresh token isn't being stored properly
   
   # Solution: Verify the token store is working
   token_store = Adk::Auth::TokenStore.new(session)
   token_store.store(cache_key, token)
   stored_token = token_store.get(cache_key)
   
   # Check if the refresh token is present
   puts "Refresh token preserved: #{stored_token[:refresh_token] == token[:refresh_token]}"
   ```

### OAuth2 Specific Refresh Issues

**Symptoms:**
- "Invalid grant" errors during refresh
- "Invalid client" errors
- Refresh succeeds but access_token doesn't work

**Possible Causes and Solutions:**

1. **Incorrect Client Authentication**
   ```ruby
   # Problem: Client authentication method is incorrect
   
   # Solution: Check if the provider expects client auth in header or body
   credential = Adk::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: ENV['CLIENT_ID'],
     client_secret: ENV['CLIENT_SECRET'],
     additional_params: {
       'client_authentication' => 'body'  # Or 'header'
     }
   )
   ```

2. **Refresh Token Rotation**
   ```ruby
   # Problem: The provider issues a new refresh token with each use
   
   # Solution: Update the stored token after each refresh
   token_manager.on(:refresh_success) do |token, scheme, credential|
     # The TokenManager already stores the new token
     puts "Token refreshed successfully with new refresh token"
   end
   ```

3. **Scope Mismatch**
   ```ruby
   # Problem: Requested scopes don't match the original authorization
   
   # Solution: Ensure consistency in scope requests
   scheme = Adk::Auth::Schemes::OAuth2.new(
     authorization_url: 'https://auth.example.com/authorize',
     token_url: 'https://auth.example.com/token',
     scopes: ['profile', 'email']  # Same scopes as original auth
   )
   ```

### Service Account Refresh Issues

**Symptoms:**
- JWT creation or exchange failures
- Token refresh works initially but fails later
- Permission errors after successful token acquisition

**Possible Causes and Solutions:**

1. **Service Account Key Rotation**
   ```ruby
   # Problem: The service account key has been rotated
   
   # Solution: Update your stored service account key
   credential = Adk::Auth::Credential.new(
     auth_type: :service_account,
     service_account_json: JSON.parse(File.read('updated-service-account-key.json'))
   )
   ```

2. **JWT Signing Issues**
   ```ruby
   # Problem: JWT signing failures due to algorithm mismatch
   
   # Solution: Verify the key format and algorithm
   # Most service accounts use RS256 algorithm by default
   ```

3. **Permission Changes**
   ```ruby
   # Problem: The service account permissions have been changed
   
   # Solution: Check IAM permissions in your cloud provider
   # Verify the service account still has access to requested scopes
   ```

## Debugging Techniques

### Monitoring Token Lifecycle

Use callbacks to monitor the token lifecycle:

```ruby
# Register callbacks for token lifecycle events
token_manager.on(:refresh_success) do |token, scheme, credential|
  puts "Token refreshed successfully"
  puts "New access token: #{token[:access_token].to_s[0..10]}... (truncated)"
  puts "New expires_at: #{token.expires_at}"
end

token_manager.on(:refresh_failure) do |token, scheme, credential, error|
  puts "Token refresh failed: #{error.message}"
  puts "Token scheme: #{scheme.scheme_type}"
  # Log details for debugging
end

token_manager.on(:before_expiry) do |token, scheme, credential|
  puts "Token approaching expiration, expires at: #{token.expires_at}"
  puts "Current time: #{Time.now}"
  puts "Seconds until expiry: #{token.expires_at - Time.now}"
end
```

### Inspecting Token Contents

For debugging token contents:

```ruby
# For JWT tokens (ID tokens, access tokens in some cases)
require 'jwt'

# Decode without verification (for debugging only!)
token_payload = JWT.decode(access_token, nil, false)[0]
puts "Token claims: #{token_payload.inspect}"

# Check critical fields
puts "Issued at: #{Time.at(token_payload['iat'])}"
puts "Expires at: #{Time.at(token_payload['exp'])}"
puts "Audience: #{token_payload['aud']}"
puts "Issuer: #{token_payload['iss']}"
```

### Testing Token Refresh Manually

To manually test token refresh:

```ruby
# Force a token refresh
token = token_manager.get_token(scheme, credential, force_refresh: true)
if token
  puts "Token refresh successful"
  puts "New access token: #{token[:access_token].to_s[0..10]}... (truncated)"
  puts "New expires_at: #{token.expires_at}"
else
  puts "Token refresh failed"
end
```

## Provider-Specific Issues

### Google OAuth2/Service Account

- **Refresh Token Expiration**: Google refresh tokens expire if unused for 6 months
- **Project Restrictions**: Check API quotas and restrictions in Google Cloud Console
- **Domain-Wide Delegation**: For service accounts, verify proper delegation is configured

### Microsoft Azure

- **Token Lifetime Policies**: Check Azure AD token lifetime policy configurations
- **Conditional Access**: Verify if conditional access policies affect token refresh
- **App Registration Changes**: Check for changes in app registrations that might affect tokens

### Auth0

- **Refresh Token Rotation**: Auth0 can be configured to rotate refresh tokens
- **Refresh Token Expiration**: Auth0 can set explicit refresh token expiry
- **Rate Limiting**: Check if you're hitting Auth0 rate limits during refresh

## Advanced Solutions

### Implementing Refresh Token Rotation

If your provider issues new refresh tokens on each refresh:

```ruby
token_manager.on(:refresh_success) do |token, scheme, credential|
  # The new refresh token is already stored in the token
  new_refresh_token = token[:refresh_token]
  
  # You can perform additional actions here if needed
  log_refresh_token_rotation(credential[:client_id], Time.now)
end
```

### Handling Multiple Auth Types

For applications with multiple authentication types:

```ruby
# Create different token managers or use the same one
oauth_token_manager = Adk::Auth::TokenManager.new(token_store)
service_account_token_manager = Adk::Auth::TokenManager.new(token_store)

# Get tokens for different auth types
oauth_token = oauth_token_manager.get_token(oauth_scheme, oauth_credential)
sa_token = service_account_token_manager.get_token(sa_scheme, sa_credential)
```

### Fallback Authentication

Implement fallback authentication when refresh fails:

```ruby
token = token_manager.get_token(scheme, credential)
if token.nil?
  # Token refresh failed, trigger re-authentication
  # For OAuth2/OIDC, this means restarting the authorization flow
  initiate_oauth_flow(scheme, credential)
end
```

## When to Contact Support

If you've tried all the solutions and still encounter issues:

1. **Provider Support**: Contact your OAuth provider's support with:
   - Error messages and timestamps
   - Client ID (but never share client secrets)
   - Token response data (sanitized)

2. **ADK Support**: File an issue with:
   - ADK version information
   - Reproduction steps
   - Error logs
   - Provider information

## Next Steps

- [OAuth2 Troubleshooting](./oauth2_issues): For OAuth2-specific authentication issues
- [OpenID Connect Issues](./oidc_issues): For OIDC-specific authentication issues
- [Token Security](./token_security): Best practices for token security 