# Credential Storage Issues

This guide addresses common issues related to storing and managing authentication credentials in the ADK Ruby library.

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
   credential = Adk::Auth::Credential.new(
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
   credential = Adk::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: ENV['CLIENT_ID'],      # Direct reference, no resolution
     client_secret: '${CLIENT_SECRET}' # Incorrect format
   )
   
   # Correct:
   credential = Adk::Auth::Credential.new(
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
   # docker run -e CLIENT_ID -e CLIENT_SECRET my-adk-app
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
   credential = Adk::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: 'actual-client-id-123',
     client_secret: 'actual-client-secret-456'
   )
   
   # Better:
   credential = Adk::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: 'ENV:CLIENT_ID',
     client_secret: 'ENV:CLIENT_SECRET'
   )
   
   # Even better - use a secure credential manager:
   secret_manager = Adk::Auth::SecretManager.new
   client_secret = secret_manager.get_secret('oauth2_client_secret')
   
   credential = Adk::Auth::Credential.new(
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
   
   # Better - use the built-in encryption:
   require 'adk/auth/encryption'
   
   encryptor = Adk::Auth::Encryption.new(secret: ENV['ENCRYPTION_KEY'])
   encrypted_data = encryptor.encrypt(JSON.dump(credential.to_h))
   
   # Store encrypted data
   File.write('creds.enc', encrypted_data)
   
   # Later, to decrypt:
   encrypted_data = File.read('creds.enc')
   json_data = encryptor.decrypt(encrypted_data)
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
     key: 'adk.session',
     secret: ENV['SESSION_SECRET'],
     expire_after: 86400  # 1 day in seconds
   
   # In a Rails app:
   # config/initializers/session_store.rb
   Rails.application.config.session_store :cookie_store, 
     key: '_adk_session',
     expire_after: 1.day
   ```

2. **Token Store Configuration**
   ```ruby
   # Problem: Token store not properly initialized
   
   # Solution: Ensure token store is initialized with the session
   
   # Incorrect:
   token_store = Adk::Auth::TokenStore.new  # Missing session
   
   # Correct:
   token_store = Adk::Auth::TokenStore.new(session)
   
   # For custom session stores:
   token_store = Adk::Auth::TokenStore.new(
     session,
     namespace: 'auth_tokens',  # Optional namespace
     serializer: JSON           # Optional custom serializer
   )
   ```

3. **Session Expiration**
   ```ruby
   # Problem: Session expires before tokens are used
   
   # Solution: Adjust session timeout or implement refresh mechanism
   
   # Extend session timeout
   use Rack::Session::Cookie, 
     key: 'adk.session',
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

1. **Encryption Key Issues**
   ```ruby
   # Problem: Missing or inconsistent encryption key
   
   # Solution: Ensure encryption key is consistent and available
   
   # Generate a secure encryption key
   require 'securerandom'
   encryption_key = SecureRandom.hex(32)  # 256-bit key
   puts "Generated encryption key: #{encryption_key}"
   
   # Store this key securely and consistently across app instances
   # Then use it in your application:
   encryptor = Adk::Auth::Encryption.new(secret: ENV['ENCRYPTION_KEY'])
   ```

2. **Encryption Algorithm Issues**
   ```ruby
   # Problem: Incompatible encryption algorithm or version
   
   # Solution: Use consistent encryption algorithms
   
   # Specify algorithm explicitly
   encryptor = Adk::Auth::Encryption.new(
     secret: ENV['ENCRYPTION_KEY'],
     algorithm: 'aes-256-gcm'  # Specify algorithm
   )
   ```

3. **Key Rotation**
   ```ruby
   # Problem: Need to rotate encryption keys without losing data
   
   # Solution: Implement key rotation with backward compatibility
   
   # Get token using current or legacy key
   def get_token_with_key_rotation(key, legacy_key = nil)
     begin
       # Try with current key first
       encryptor = Adk::Auth::Encryption.new(secret: key)
       return encryptor.decrypt(encrypted_data)
     rescue Adk::Auth::EncryptionError
       if legacy_key
         # Try with legacy key
         legacy_encryptor = Adk::Auth::Encryption.new(secret: legacy_key)
         
         # If successful with legacy key, re-encrypt with new key
         decrypted = legacy_encryptor.decrypt(encrypted_data)
         new_encrypted = encryptor.encrypt(decrypted)
         
         # Save with new encryption
         save_encrypted_data(new_encrypted)
         
         return decrypted
       else
         raise  # Re-raise if no legacy key available
       end
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
   
   # In your code:
   begin
     service_account_json = ENV['SERVICE_ACCOUNT_JSON']
     key_data = JSON.parse(service_account_json)
     
     credential = Adk::Auth::Credential.new(
       auth_type: :service_account,
       service_account_json: key_data
     )
   rescue JSON::ParserError => e
     puts "Invalid service account JSON in environment variable: #{e.message}"
   end
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
   
   credential = Adk::Auth::Credential.new(
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
  when :service_account
    required = [:service_account_json]
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
credential = Adk::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: 'ENV:CLIENT_ID',
  client_secret: 'ENV:CLIENT_SECRET'
)

validate_credential(credential)
```

### TokenStore Debugging

For debugging token store issues:

```ruby
# Debug token store
def debug_token_store(token_store)
  # List all keys in token store
  all_keys = token_store.all_keys
  puts "Token store has #{all_keys.size} keys:"
  all_keys.each do |key|
    puts "- #{key}"
    
    # Check if token can be retrieved
    begin
      token = token_store.get(key)
      if token
        puts "  Token type: #{token.auth_type}"
        puts "  Expires at: #{token.expires_at}"
        puts "  Can refresh: #{token.can_refresh? ? 'Yes' : 'No'}"
      else
        puts "  Token not found"
      end
    rescue => e
      puts "  Error retrieving token: #{e.message}"
    end
  end
end

# Usage
token_store = Adk::Auth::TokenStore.new(session)
debug_token_store(token_store)
```

## When to Contact Support

If you've tried all the solutions and still encounter issues:

1. **Check for Library Updates**:
   - Verify you're using the latest version of the ADK Ruby library
   - Check the changelog for fixes related to credential storage

2. **Debug Information to Collect**:
   - ADK Ruby version
   - Ruby version and platform
   - Environment (development, production)
   - Error messages (with sensitive data redacted)
   - Steps to reproduce the issue

3. **Contact ADK Support**:
   - Provide collected debug information
   - Describe your credential storage setup
   - Share reproduction steps

## Next Steps

- [Token Lifecycle Management](../guides/token_lifecycle.md): Advanced token management techniques
- [OAuth2 Troubleshooting](./oauth2_issues.md): For OAuth2-specific authentication issues
- [Environment Variable Management](./environment_variables.md): Best practices for handling environment variables 