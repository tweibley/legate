# OpenID Connect Authentication Issues

This guide addresses common issues encountered when implementing and using OpenID Connect (OIDC) authentication in the ADK Ruby library.

## Common OpenID Connect Issues

### Discovery URL Problems

**Symptoms:**
- "Unable to fetch discovery document" errors
- Connection timeout when initializing OIDC scheme
- JSON parsing errors during setup

**Possible Causes and Solutions:**

1. **Incorrect Discovery URL**
   ```ruby
   # Problem: The discovery URL is incorrect or malformed
   
   # Solution: Verify the discovery URL
   scheme = Adk::Auth::Schemes::OpenIDConnect.new(
     # Incorrect URL
     # discovery_url: 'https://accounts.google.com/openid-configuration'
     
     # Correct URL
     discovery_url: 'https://accounts.google.com/.well-known/openid-configuration'
   )
   ```

2. **Network/Connectivity Issues**
   ```ruby
   # Problem: Network connectivity issues prevent access to the discovery document
   
   # Solution: Implement retry logic or manually specify endpoints
   scheme = Adk::Auth::Schemes::OpenIDConnect.new(
     # Fall back to manual configuration if discovery fails
     authorization_url: 'https://accounts.google.com/o/oauth2/auth',
     token_url: 'https://oauth2.googleapis.com/token',
     userinfo_url: 'https://openidconnect.googleapis.com/v1/userinfo',
     jwks_url: 'https://www.googleapis.com/oauth2/v3/certs',
     scopes: ['openid', 'profile', 'email']
   )
   ```

3. **Provider Service Outage**
   ```ruby
   # Problem: The identity provider's discovery endpoint is down
   
   # Solution: Implement caching of discovery document
   # Example implementation of discovery caching
   
   def get_cached_discovery(url, cache_ttl = 86400)
     cache_key = "oidc_discovery_#{Digest::MD5.hexdigest(url)}"
     cached = session[:cache]&.dig(cache_key)
     
     if cached && cached[:timestamp] > Time.now.to_i - cache_ttl
       return cached[:document]
     end
     
     response = HTTP.get(url)
     document = JSON.parse(response.body.to_s)
     
     session[:cache] ||= {}
     session[:cache][cache_key] = {
       timestamp: Time.now.to_i,
       document: document
     }
     
     document
   end
   ```

### ID Token Validation Issues

**Symptoms:**
- "Invalid token signature" errors
- "Invalid issuer" or "Invalid audience" errors
- "Token expired" errors when the token should be valid

**Possible Causes and Solutions:**

1. **Signature Verification Issues**
   ```ruby
   # Problem: Unable to verify ID token signature
   
   # Solution: Ensure JWKS endpoint is correctly specified
   scheme = Adk::Auth::Schemes::OpenIDConnect.new(
     discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
     jwks_cache_ttl: 3600  # Cache JWKS for 1 hour to reduce failures
   )
   
   # For debugging, print token details (don't do this in production)
   require 'jwt'
   decoded_token = JWT.decode(id_token, nil, false)[0]
   puts "Token headers: #{JWT.decode(id_token, nil, false)[1]}"
   puts "Token claims: #{decoded_token}"
   ```

2. **Clock Skew Issues**
   ```ruby
   # Problem: Server time is out of sync with the identity provider
   
   # Solution: Allow for clock skew when validating tokens
   token_validator = Adk::Auth::TokenValidator.new(
     leeway: 60  # Allow 60 seconds of clock skew
   )
   
   # Or sync your server time
   # On Linux: sudo ntpdate time.google.com
   # On macOS: sudo sntp -sS time.apple.com
   ```

3. **Incorrect Audience or Issuer**
   ```ruby
   # Problem: The token's audience or issuer doesn't match expected values
   
   # Solution: Specify the expected values
   scheme = Adk::Auth::Schemes::OpenIDConnect.new(
     discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
     additional_validation: {
       issuer: 'https://accounts.google.com',
       audience: ENV['CLIENT_ID']  # Must match your client ID
     }
   )
   ```

### Scope-Related Issues

**Symptoms:**
- Missing profile information
- "Invalid scope" errors
- ID token doesn't contain expected claims

**Possible Causes and Solutions:**

1. **Missing 'openid' Scope**
   ```ruby
   # Problem: The 'openid' scope is missing
   
   # Solution: Always include 'openid' scope for OIDC
   scheme = Adk::Auth::Schemes::OpenIDConnect.new(
     discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
     # Incorrect: scopes: ['profile', 'email']
     
     # Correct:
     scopes: ['openid', 'profile', 'email']  # 'openid' is required for OIDC
   )
   ```

2. **Insufficient Scopes for Desired Claims**
   ```ruby
   # Problem: The token doesn't contain required user information
   
   # Solution: Request additional scopes
   scheme = Adk::Auth::Schemes::OpenIDConnect.new(
     discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
     scopes: ['openid', 'profile', 'email', 'address', 'phone']  # Request more information
   )
   ```

3. **Provider-Specific Scope Format**
   ```ruby
   # Problem: The provider requires scopes in a specific format
   
   # Solution: Format scopes according to provider requirements
   
   # For Microsoft Azure AD, use full URL format for scopes
   scheme = Adk::Auth::Schemes::OpenIDConnect.new(
     discovery_url: 'https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration',
     scopes: [
       'openid',
       'profile',
       'email',
       'https://graph.microsoft.com/User.Read'
     ]
   )
   ```

### Authentication Flow Issues

**Symptoms:**
- Users redirected to incorrect URLs
- Authentication callbacks failing
- "State mismatch" errors
- "Invalid redirect URI" errors

**Possible Causes and Solutions:**

1. **Incorrect Redirect URI**
   ```ruby
   # Problem: The redirect URI doesn't match what's registered with the provider
   
   # Solution: Use exactly the same redirect URI as registered
   scheme = Adk::Auth::Schemes::OpenIDConnect.new(
     discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
     scopes: ['openid', 'profile', 'email']
   )
   
   # Generate auth config with exact matching redirect URI
   config = scheme.generate_auth_config(
     credential,
     callback_url: 'https://exact-registered-uri.example.com/callback'  # Must match exactly
   )
   ```

2. **State Parameter Issues**
   ```ruby
   # Problem: The state parameter is missing or mismatched
   
   # Solution: Verify that state is preserved in the callback
   auth_response = {
     auth_request_id: config.auth_request_id,
     auth_response_uri: callback_uri_with_state
   }
   
   # For debugging, check the state parameter
   uri = URI.parse(callback_uri_with_state)
   params = CGI.parse(uri.query || '')
   state = params['state']&.first
   
   puts "Expected state: #{config.callback_params[:state]}"
   puts "Received state: #{state}"
   ```

3. **Invalid Response Type**
   ```ruby
   # Problem: Using the wrong response type
   
   # Solution: Specify the correct response type 
   scheme = Adk::Auth::Schemes::OpenIDConnect.new(
     discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
     scopes: ['openid', 'profile', 'email'],
     additional_params: {
       'response_type' => 'code'  # The standard for authorization code flow
     }
   )
   ```

## Provider-Specific Issues

### Google OpenID Connect

1. **Consent Screen Configuration**
   - Ensure you've configured the OAuth consent screen in the Google Cloud Console
   - Verify that you've added all the scopes you request to the allowed scopes

2. **Refresh Token Issues**
   ```ruby
   # Problem: Not receiving a refresh token
   
   # Solution: Request offline access
   scheme = Adk::Auth::Schemes::OpenIDConnect.new(
     discovery_url: 'https://accounts.google.com/.well-known/openid-configuration',
     scopes: ['openid', 'profile', 'email'],
     additional_params: {
       'access_type' => 'offline',
       'prompt' => 'consent'  # Force consent screen to appear
     }
   )
   ```

3. **Domain Restrictions**
   - Check if your Google Workspace settings restrict access to specific domains
   - Verify that your authorized domains are correctly configured

### Microsoft Azure AD

1. **Tenant Configuration**
   ```ruby
   # Problem: Using the wrong tenant
   
   # Solution: Specify the correct tenant ID
   tenant_id = 'common'  # Use 'common' for multi-tenant, or a specific tenant ID
   
   scheme = Adk::Auth::Schemes::OpenIDConnect.new(
     discovery_url: "https://login.microsoftonline.com/#{tenant_id}/v2.0/.well-known/openid-configuration",
     scopes: ['openid', 'profile', 'email', 'offline_access']
   )
   ```

2. **App Registration Issues**
   - Ensure you've granted admin consent for the required permissions
   - Check that the API permissions in your app registration match your requested scopes

3. **Conditional Access Policies**
   - Conditional access policies might block authentication
   - Verify that your app isn't blocked by conditional access policies

### Auth0

1. **Audience Parameter**
   ```ruby
   # Problem: Missing audience parameter for Auth0
   
   # Solution: Specify the audience
   domain = 'your-domain.auth0.com'
   
   scheme = Adk::Auth::Schemes::OpenIDConnect.new(
     discovery_url: "https://#{domain}/.well-known/openid-configuration",
     scopes: ['openid', 'profile', 'email'],
     additional_params: {
       'audience' => 'https://api.example.com'  # Your API identifier
     }
   )
   ```

2. **Rules and Actions**
   - Auth0 rules or actions might be modifying the authentication flow
   - Check your Auth0 dashboard for rules that might affect your authentication

## Debugging Techniques

### Inspecting ID Tokens

For debugging ID token issues:

```ruby
# Decode and inspect an ID token
require 'jwt'

# Decode without verification (for debugging only!)
token_parts = JWT.decode(id_token, nil, false)
token_payload = token_parts[0]
token_header = token_parts[1]

puts "Token header: #{token_header.inspect}"
puts "Token payload: #{token_payload.inspect}"

# Check critical claims
puts "Issuer: #{token_payload['iss']}"
puts "Subject: #{token_payload['sub']}"
puts "Audience: #{token_payload['aud']}"
puts "Expiration: #{Time.at(token_payload['exp'])}"
puts "Issued at: #{Time.at(token_payload['iat'])}"
puts "Available claims: #{token_payload.keys.join(', ')}"
```

### Debugging UserInfo Endpoint

For debugging userinfo endpoint issues:

```ruby
# Manually call the userinfo endpoint
require 'http'

access_token = exchanged_credential[:access_token]
userinfo_url = scheme.userinfo_url || 'https://provider.example.com/userinfo'

response = HTTP.auth("Bearer #{access_token}")
              .get(userinfo_url)

if response.status.success?
  user_info = JSON.parse(response.body.to_s)
  puts "UserInfo response: #{user_info.inspect}"
else
  puts "UserInfo error: #{response.status} - #{response.body}"
end
```

### PKCE Verification

For debugging PKCE-related issues:

```ruby
# Manually trace PKCE parameters
code_verifier = "random_secure_string_of_at_least_43_characters"
require 'base64'
require 'digest'

# Generate code_challenge (S256 method)
code_challenge = Base64.urlsafe_encode64(
  Digest::SHA256.digest(code_verifier)
).gsub(/=+$/, '')

puts "Code verifier: #{code_verifier}"
puts "Code challenge: #{code_challenge}"

# Use these in manual authorization request
auth_url = "https://provider.example.com/authorize" \
           "?client_id=#{client_id}" \
           "&response_type=code" \
           "&code_challenge=#{code_challenge}" \
           "&code_challenge_method=S256"
```

## When All Else Fails

If you've tried all the solutions and still encounter issues:

1. **Check IdP Logs**:
   - Most identity providers offer authentication logs
   - Review logs for your client ID around the time of failure

2. **Use OpenID Connect Debuggers**:
   - [OpenID Connect Debugger](https://oidcdebugger.com/)
   - [Auth0 JWT Debugger](https://jwt.io/)

3. **Contact Provider Support**:
   - Provide detailed error messages and timestamps
   - Share your client ID (but never share client secrets)

## Next Steps

- [OAuth2 Troubleshooting](./oauth2_issues.md): For OAuth2-specific issues
- [Token Refresh Problems](./token_refresh.md): For issues with token refresh
- [Credential Storage Issues](./credential_storage.md): For issues with storing credentials 