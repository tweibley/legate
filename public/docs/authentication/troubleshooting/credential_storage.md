# Credential Storage Issues

This guide addresses common issues related to storing and managing authentication credentials in the Legate Ruby library.

## Common Credential Storage Issues

### Environment Variable Resolution

**Symptoms:**
- "Environment variable not found" errors
- Authentication failing despite credentials being set
- Credentials not being loaded correctly

**Possible Causes and Solutions:**

1. **Missing Environment Variables**
   ```ruby
   # Problem: Environment variable referenced but not set
   
   # Solution: Ensure environment variables are set before running
   # In your shell:
   export CLIENT_ID="your-client-id"
   export CLIENT_SECRET="your-client-secret"
   
   # In Ruby, verify environment variables are set
   if ENV['CLIENT_ID'].nil? || ENV['CLIENT_SECRET'].nil?
     puts "ERROR: Required environment variables are not set"
     exit 1
   end
   
   # Then use in credential
   credential = Legate::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: 'ENV:CLIENT_ID',
     client_secret: 'ENV:CLIENT_SECRET'
   )
   ```

2. **Incorrect Environment Variable References**
   ```ruby
   # Problem: Incorrect prefix or format for environment variable reference
   
   # Solution: Use the correct format with 'ENV:' prefix
   
   # Incorrect:
   credential = Legate::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: ENV['CLIENT_ID'],      # Direct reference, no resolution
     client_secret: '${CLIENT_SECRET}' # Incorrect format
   )
   
   # Correct:
   credential = Legate::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: 'ENV:CLIENT_ID',       # Proper environment variable reference
     client_secret: 'ENV:CLIENT_SECRET'
   )
   ```

3. **Environment Scope Issues**
   ```ruby
   # Problem: Environment variables not accessible to the process
   
   # Solution: Verify environment variables are in the correct scope
   
   # Check if variables are accessible
   puts "CLIENT_ID: #{ENV['CLIENT_ID'] ? 'Set' : 'Not set'}"
   puts "CLIENT_SECRET: #{ENV['CLIENT_SECRET'] ? 'Set' : 'Not set'}"
   
   # For containerized applications, ensure variables are passed to the container
   # docker run -e CLIENT_ID -e CLIENT_SECRET my-legate-app
   ```

### Secure Credential Storage

**Symptoms:**
- Security warnings about hardcoded credentials
- Credentials exposed in logs or errors
- Unauthorized access to sensitive credentials

**Possible Causes and Solutions:**

1. **Hardcoded Credentials**
   ```ruby
   # Problem: Credentials hardcoded in source code
   
   # Solution: Use environment variables or secure credential stores
   
   # Incorrect (avoid this):
   credential = Legate::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: 'actual-client-id-123',
     client_secret: 'actual-client-secret-456'
   )
   
   # Better:
   credential = Legate::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: 'ENV:CLIENT_ID',
     client_secret: 'ENV:CLIENT_SECRET'
   )
   
   # Even better - resolve the secret from your own secrets manager
   # (e.g. Vault, AWS Secrets Manager) before constructing the credential:
   client_secret = MySecretsClient.fetch('oauth2_client_secret')
   
   credential = Legate::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: 'ENV:CLIENT_ID',
     client_secret: client_secret
   )
   ```

2. **Credential Logging**
   ```ruby
   # Problem: Sensitive credentials appear in logs
   
   # Solution: Implement secure logging and avoid logging credentials
   
   # Unsafe:
   logger.info "Using credential: #{credential.to_h}"
   
   # Better:
   logger.info "Using credential type: #{credential.auth_type}"
   
   # For debugging, sanitize sensitive fields:
   safe_cred = credential.to_h
   safe_cred[:client_secret] = "[REDACTED]" if safe_cred[:client_secret]
   safe_cred[:api_key] = "[REDACTED]" if safe_cred[:api_key]
   logger.debug "Using credential (sanitized): #{safe_cred}"
   ```

3. **Insecure Storage**
   ```ruby
   # Problem: Credentials stored insecurely on disk
   
   # Solution: Use proper encryption for saved credentials
   
   # Incorrect - storing credentials in plain text:
   File.write('creds.json', JSON.dump(credential.to_h))
   
   # Better - use the opt-in Encryption module (module methods, not instances).
   # Requires the rbnacl gem and a Base64 key (see generate_key).
   require 'legate/auth/encryption'
   
   key = ENV['LEGATE_AUTH_ENCRYPTION_KEY'] # Base64-encoded; or Encryption.generate_key
   encrypted_data = Legate::Auth::Encryption.encrypt(JSON.dump(credential.to_h), key)
   
   # Store encrypted data
   File.write('creds.enc', encrypted_data)
   
   # Later, to decrypt:
   encrypted_data = File.read('creds.enc')
   json_data = Legate::Auth::Encryption.decrypt(encrypted_data, key)
   cred_hash = JSON.parse(json_data)
   ```

### Session Storage Issues

**Symptoms:**
- Tokens disappearing between requests
- "Session not found" errors
- Authentication state not persisting

**Possible Causes and Solutions:**

1. **Session Configuration**
   ```ruby
   # Problem: Session not configured properly
   
   # Solution: Configure session with proper settings
   
   # In a Sinatra app:
   use Rack::Session::Cookie, 
     key: 'legate.session',
     secret: ENV['SESSION_SECRET'],
     expire_after: 86400  # 1 day in seconds

   # In a Rails app:
   # config/initializers/session_store.rb
   Rails.application.config.session_store :cookie_store,
     key: '_legate_session',
     expire_after: 1.day
   ```

2. **Token Store Configuration**
   ```ruby
   # Problem: Token store not properly initialized
   
   # Solution: Ensure token store is initialized with the session
   
   # Incorrect:
   token_store = Legate::Auth::TokenStore.new  # Missing session service
   
   # Correct: pass the session service positionally
   token_store = Legate::Auth::TokenStore.new(session_service)
   
   # Note: TokenStore.new takes a single positional argument (the session
   # service). It does not accept namespace/serializer keyword options; tokens
   # are stored under the fixed 'auth' scope.
   ```

3. **Session Expiration**
   ```ruby
   # Problem: Session expires before tokens are used
   
   # Solution: Adjust session timeout or implement refresh mechanism
   
   # Extend session timeout
   use Rack::Session::Cookie, 
     key: 'legate.session',
     secret: ENV['SESSION_SECRET'],
     expire_after: 604800  # 1 week in seconds
   
   # Or implement periodic session refresh
   before do
     # Refresh session on each request
     session[:last_activity] = Time.now.to_i
   end
   ```

## Encryption-Related Issues

**Symptoms:**
- "Decryption failed" errors
- "Invalid encryption key" errors
- Tokens cannot be retrieved from storage

**Possible Causes and Solutions:**

> **Note:** `Legate::Auth::Encryption` is an opt-in module (not wired into `TokenStore`) and is not instantiable — call its module methods directly. It uses rbnacl (libsodium SecretBox) and requires the `rbnacl` gem. Decryption failures raise `ArgumentError`; a missing `rbnacl` gem raises `LoadError`. There is no `EncryptionError` class and no algorithm option.

1. **Encryption Key Issues**
   ```ruby
   # Problem: Missing or inconsistent encryption key
   
   # Solution: Generate a Base64 key with generate_key and keep it consistent
   require 'legate/auth/encryption'
   encryption_key = Legate::Auth::Encryption.generate_key  # Base64-encoded
   puts "Generated encryption key: #{encryption_key}"
   
   # Store this key securely (e.g. LEGATE_AUTH_ENCRYPTION_KEY) and reuse it
   # consistently across app instances:
   encrypted = Legate::Auth::Encryption.encrypt(data, ENV['LEGATE_AUTH_ENCRYPTION_KEY'])
   ```

2. **Wrong Key or Tampered Data**
   ```ruby
   # Problem: Decryption fails (wrong key, bad format, or tampered ciphertext)
   
   # Solution: Decryption failures raise ArgumentError; handle them explicitly
   begin
     plaintext = Legate::Auth::Encryption.decrypt(encrypted_data, key)
   rescue ArgumentError => e
     puts "Decryption failed: #{e.message}"
   end
   ```

3. **Key Rotation**
   ```ruby
   # Problem: Need to rotate encryption keys without losing data
   
   # Solution: Implement key rotation with backward compatibility
   def get_token_with_key_rotation(encrypted_data, key, legacy_key = nil)
     begin
       # Try with current key first
       return Legate::Auth::Encryption.decrypt(encrypted_data, key)
     rescue ArgumentError
       raise unless legacy_key
       # Try with legacy key, then re-encrypt with the new key
       decrypted = Legate::Auth::Encryption.decrypt(encrypted_data, legacy_key)
       new_encrypted = Legate::Auth::Encryption.encrypt(decrypted, key)
       save_encrypted_data(new_encrypted)
       decrypted
     end
   end
   ```

## Service Account Key Issues

**Symptoms:**
- "Invalid key format" errors
- JSON parsing errors with service account keys
- Authentication failing with service accounts

**Possible Causes and Solutions:**

1. **JSON Key Format Issues**
   ```ruby
   # Problem: Service account key JSON is malformed
   
   # Solution: Ensure JSON is valid and complete
   
   # Verify key format
   begin
     key_data = JSON.parse(File.read('service-account-key.json'))
     required_fields = ['type', 'project_id', 'private_key_id', 'private_key', 
                        'client_email', 'client_id', 'auth_uri', 'token_uri']
     
     missing = required_fields - key_data.keys
     if missing.any?
       puts "Invalid key file: Missing fields: #{missing.join(', ')}"
     else
       puts "Key file appears valid"
     end
   rescue JSON::ParserError => e
     puts "Invalid JSON: #{e.message}"
   end
   ```

2. **Key Environment Variable Issues**
   ```ruby
   # Problem: Service account key environment variable is malformed
   
   # Solution: Ensure JSON is properly escaped in the environment variable
   
   # The environment variable must contain valid JSON:
   # export SERVICE_ACCOUNT_JSON='{"type":"service_account","project_id":"...","private_key":"...","client_email":"..."}'
   
   # In your code (pass the raw JSON string via service_account_key, not a
   # parsed Hash; the attribute is service_account_key, not service_account_json):
   service_account_json = ENV['SERVICE_ACCOUNT_JSON']
   begin
     JSON.parse(service_account_json)  # validate it parses
   rescue JSON::ParserError => e
     puts "Invalid service account JSON in environment variable: #{e.message}"
   end

   credential = Legate::Auth::Credential.new(
     auth_type: :service_account,
     service_account_key: service_account_json  # raw JSON string
   )

   # Or reference the env var directly:
   # service_account_key: 'ENV:SERVICE_ACCOUNT_JSON'
   ```

3. **Key File Permissions**
   ```ruby
   # Problem: Key file has incorrect permissions
   
   # Solution: Set restrictive file permissions
   
   # In your terminal:
   chmod 0600 service-account-key.json  # Owner read/write only
   
   # In your code, check permissions:
   key_file = 'service-account-key.json'
   permissions = File.stat(key_file).mode & 0777
   
   if permissions > 0600
     puts "WARNING: Key file permissions are too permissive: #{permissions.to_s(8)}"
     puts "Consider restricting permissions with: chmod 0600 #{key_file}"
   end
   ```

## Multi-Environment Configuration

**Symptoms:**
- Credentials work in development but fail in production
- Different behavior across environments
- Configuration errors in deployed applications

**Possible Causes and Solutions:**

1. **Environment-Specific Credentials**
   ```ruby
   # Problem: Using the same credentials across environments
   
   # Solution: Use environment-specific credential configuration
   
   # Load different credentials based on environment
   environment = ENV['RACK_ENV'] || 'development'
   
   case environment
   when 'development'
     client_id = 'ENV:DEV_CLIENT_ID'
     client_secret = 'ENV:DEV_CLIENT_SECRET'
   when 'production'
     client_id = 'ENV:PROD_CLIENT_ID'
     client_secret = 'ENV:PROD_CLIENT_SECRET'
   end
   
   credential = Legate::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: client_id,
     client_secret: client_secret
   )
   ```

2. **Configuration Loading Issues**
   ```ruby
   # Problem: Configuration not loaded in the correct order
   
   # Solution: Establish clear configuration loading order
   
   # Example configuration loader
   def load_configuration
     # 1. Load defaults
     config = {
       oauth2: {
         client_id: nil,
         client_secret: nil
       }
     }
     
     # 2. Override with environment-specific configuration file
     env_config_file = "config/#{ENV['RACK_ENV'] || 'development'}.yml"
     if File.exist?(env_config_file)
       env_config = YAML.load_file(env_config_file)
       config.deep_merge!(env_config)
     end
     
     # 3. Override with environment variables
     config[:oauth2][:client_id] = ENV['OAUTH_CLIENT_ID'] if ENV['OAUTH_CLIENT_ID']
     config[:oauth2][:client_secret] = ENV['OAUTH_CLIENT_SECRET'] if ENV['OAUTH_CLIENT_SECRET']
     
     config
   end
   ```

3. **Environment Variable Names**
   ```ruby
   # Problem: Inconsistent environment variable naming across environments
   
   # Solution: Standardize environment variable names
   
   # Create a mapping between standard names and environment-specific names
   env_var_mapping = {
     development: {
       client_id: 'DEV_CLIENT_ID',
       client_secret: 'DEV_CLIENT_SECRET'
     },
     production: {
       client_id: 'PROD_CLIENT_ID',
       client_secret: 'PROD_CLIENT_SECRET'
     }
   }
   
   environment = (ENV['RACK_ENV'] || 'development').to_sym
   mapping = env_var_mapping[environment]
   
   client_id = "ENV:#{mapping[:client_id]}"
   client_secret = "ENV:#{mapping[:client_secret]}"
   ```

## Debugging Techniques

### Credential Validation

For debugging credential issues:

```ruby
# Validate a credential
def validate_credential(credential)
  puts "Credential type: #{credential.auth_type}"
  
  case credential.auth_type
  when :oauth2, :oidc
    required = [:client_id, :client_secret]
  when :api_key
    required = [:api_key]
  when :service_account, :google_service_account
    # Either service_account_key (raw JSON string) or service_account_key_file
    required = [:service_account_key]
  end
  
  missing = required.select { |attr| credential[attr].nil? }
  if missing.any?
    puts "ERROR: Missing required attributes: #{missing.join(', ')}"
  else
    puts "Credential appears valid"
  end
  
  # Check environment variable resolution
  required.each do |attr|
    value = credential[attr, resolve_env: false]
    if value.is_a?(String) && value.start_with?('ENV:')
      env_var = value.sub(/^ENV:/, '')
      if ENV[env_var].nil?
        puts "WARNING: Environment variable not set: #{env_var}"
      else
        puts "Environment variable resolved: #{env_var}"
      end
    end
  end
end

# Usage
credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'ENV:CLIENT_ID',
  client_secret: 'ENV:CLIENT_SECRET'
)

validate_credential(credential)
```

### TokenStore Debugging

For debugging token store issues:

`TokenStore` does not expose a method to enumerate keys (there is no `all_keys`). Debug a specific token by looking it up by its key:

```ruby
# Debug a single token by key
def debug_token(token_store, key)
  token = token_store.get(key)
  if token
    puts "Token type: #{token.auth_type}"
    puts "Expires at: #{token[:expires_at]}"
    puts "Expired?: #{token.expired?}"
    puts "Refreshable: #{token.refreshable? ? 'Yes' : 'No'}"  # use refreshable?, not can_refresh?
  else
    puts "Token not found or expired for key: #{key}"
  end
rescue => e
  puts "Error retrieving token: #{e.message}"
end

# Usage
token_store = Legate::Auth::TokenStore.new(session_service)
debug_token(token_store, 'auth_<hash>')
```

## When to Contact Support

If you've tried all the solutions and still encounter issues:

1. **Check for Library Updates**:
   - Verify you're using the latest version of the Legate Ruby library
   - Check the changelog for fixes related to credential storage

2. **Debug Information to Collect**:
   - Legate Ruby version
   - Ruby version and platform
   - Environment (development, production)
   - Error messages (with sensitive data redacted)
   - Steps to reproduce the issue

3. **Contact Legate Support**:
   - Provide collected debug information
   - Describe your credential storage setup
   - Share reproduction steps

## Next Steps

- [Token Lifecycle Management](../guides/token_lifecycle): Advanced token management techniques
- [OAuth2 Troubleshooting](./oauth2_issues): For OAuth2-specific authentication issues
- [Environment Variable Management](./environment_variables): Best practices for handling environment variables 