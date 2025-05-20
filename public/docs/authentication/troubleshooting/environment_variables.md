# Environment Variable Management

This guide covers best practices and troubleshooting for environment variables used with the ADK Ruby library's authentication system.

## Overview

The ADK Ruby library uses environment variables for storing sensitive credentials and configuration settings. This approach separates sensitive data from your code, improving security and making your application more portable across different environments.

## Environment Variable Best Practices

### Naming Conventions

Use consistent naming conventions for your environment variables:

```ruby
# Preferred naming pattern
CLIENT_ID                  # General purpose
GOOGLE_CLIENT_ID           # Provider-specific
DEV_CLIENT_ID              # Environment-specific
DEV_GOOGLE_CLIENT_ID       # Environment and provider-specific
```

### Security Considerations

1. **Never Commit Environment Variables**:
   ```bash
   # Add environment files to .gitignore
   echo ".env" >> .gitignore
   echo ".env.*" >> .gitignore
   ```

2. **Use Different Values Across Environments**:
   ```bash
   # Development environment
   export DEV_CLIENT_ID="dev-client-id"
   export DEV_CLIENT_SECRET="dev-client-secret"
   
   # Production environment
   export PROD_CLIENT_ID="prod-client-id"
   export PROD_CLIENT_SECRET="prod-client-secret"
   ```

3. **Limit Access to Environment Variables**:
   ```bash
   # Set restrictive permissions on environment files
   chmod 600 .env
   ```

## Common Issues and Solutions

### Missing Environment Variables

**Symptoms:**
- "Environment variable not found" errors
- Authentication failing with no clear error

**Possible Causes and Solutions:**

1. **Environment File Not Loaded**
   ```ruby
   # Problem: .env file not loaded
   
   # Solution: Use a library like dotenv
   require 'dotenv'
   Dotenv.load  # Load .env file
   
   # Or load environment-specific files
   Dotenv.load(".env.#{ENV['RACK_ENV'] || 'development'}")
   ```

2. **Environment Variable Not Set in Current Shell**
   ```bash
   # Problem: Variable set in one shell but not available in another
   
   # Solution: Verify the variable is set in the current shell
   echo $CLIENT_ID
   
   # If not set, set it:
   export CLIENT_ID="your-client-id"
   
   # Add to shell profile for persistence:
   echo 'export CLIENT_ID="your-client-id"' >> ~/.bash_profile
   ```

3. **Environment Variables in Production**
   ```ruby
   # Problem: Environment variables not set in production environment
   
   # Solution: Set environment variables at the system or container level
   
   # For Heroku:
   # heroku config:set CLIENT_ID=your-client-id
   
   # For Docker:
   # docker run -e CLIENT_ID=your-client-id -e CLIENT_SECRET=your-client-secret your-app
   ```

### Environment Variable Resolution

**Symptoms:**
- Authentication failing with credential errors
- Environment variables not being properly resolved

**Possible Causes and Solutions:**

1. **Incorrect Reference Format**
   ```ruby
   # Problem: Incorrect environment variable reference format
   
   # Solution: Use the correct 'ENV:' prefix
   
   # Incorrect:
   credential = Adk::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: "$CLIENT_ID",         # Wrong format
     client_secret: "${CLIENT_SECRET}" # Wrong format
   )
   
   # Correct:
   credential = Adk::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: "ENV:CLIENT_ID",        # Correct format
     client_secret: "ENV:CLIENT_SECRET" # Correct format
   )
   ```

2. **Case Sensitivity Issues**
   ```ruby
   # Problem: Environment variable case mismatch
   
   # Solution: Use consistent case
   
   # If environment variable is defined as:
   # export CLIENT_ID="your-client-id"
   
   # This won't work:
   credential = Adk::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: "ENV:client_id"  # Wrong case
   )
   
   # This will work:
   credential = Adk::Auth::Credential.new(
     auth_type: :oauth2,
     client_id: "ENV:CLIENT_ID"  # Correct case
   )
   ```

3. **Debug Environment Variable Resolution**
   ```ruby
   # To debug environment variable resolution:
   def debug_env_var(name)
     puts "Checking environment variable: #{name}"
     
     if ENV[name]
       puts "✓ Environment variable is set"
       puts "Value length: #{ENV[name].length} characters"
       puts "Value preview: #{ENV[name][0..5]}..." if ENV[name].length > 0
     else
       puts "✗ Environment variable is NOT set"
       puts "Available env vars: #{ENV.keys.grep(/#{name}/i).join(', ')}"
     end
   end
   
   # Usage:
   debug_env_var('CLIENT_ID')
   debug_env_var('CLIENT_SECRET')
   ```

### Service Account JSON in Environment Variables

**Symptoms:**
- JSON parsing errors with service account keys
- Malformed service account credentials

**Possible Causes and Solutions:**

1. **Escaping Issues**
   ```ruby
   # Problem: JSON escaping issues in the environment variable
   
   # Solution: Properly escape the JSON string
   
   # Incorrect (newlines and quotes will cause issues):
   # export SERVICE_ACCOUNT_JSON='{"private_key":"-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n"}'
   
   # Better approach - base64 encode the JSON:
   # 1. Encode the file to base64
   base64_key=$(base64 -i service-account-key.json)
   
   # 2. Set the environment variable with the base64 string
   export SERVICE_ACCOUNT_JSON_BASE64="$base64_key"
   
   # 3. In your code, decode the base64 string
   require 'base64'
   json_string = Base64.decode64(ENV['SERVICE_ACCOUNT_JSON_BASE64'])
   key_data = JSON.parse(json_string)
   
   credential = Adk::Auth::Credential.new(
     auth_type: :service_account,
     service_account_json: key_data
   )
   ```

2. **Size Limitations**
   ```ruby
   # Problem: Environment variable too large
   
   # Solution: Use a file-based approach instead
   
   # Option 1: Store the service account key in a file
   # This is often better for large service account keys
   
   credential = Adk::Auth::Credential.new(
     auth_type: :service_account,
     service_account_key_file: 'path/to/service-account-key.json'
   )
   
   # Option 2: Use a secret management service
   # Example with AWS Secrets Manager:
   require 'aws-sdk-secretsmanager'
   
   client = Aws::SecretsManager::Client.new(region: 'us-west-2')
   secret = client.get_secret_value(secret_id: 'my-service-account-key')
   key_data = JSON.parse(secret.secret_string)
   
   credential = Adk::Auth::Credential.new(
     auth_type: :service_account,
     service_account_json: key_data
   )
   ```

### Environment Variable Loading Order

**Symptoms:**
- Unexpected environment variable values
- Environment variables overwritten unexpectedly

**Possible Causes and Solutions:**

1. **Multiple Environment Files**
   ```ruby
   # Problem: Multiple environment files with conflicting variables
   
   # Solution: Establish a clear loading order
   
   # With dotenv, you can control the order:
   require 'dotenv'
   
   # Load in this order (later files override earlier ones):
   Dotenv.load('.env.local.development') # Local development overrides
   Dotenv.load('.env.development')       # Environment-specific defaults
   Dotenv.load('.env.local')             # Local overrides
   Dotenv.load('.env')                   # Default values
   ```

2. **Application Code Overwriting Environment Variables**
   ```ruby
   # Problem: Code overwrites environment variables
   
   # Solution: Don't modify ENV directly, use a configuration layer
   
   # Avoid this:
   ENV['CLIENT_ID'] = 'hardcoded-value' # Don't do this!
   
   # Better approach - use a configuration object:
   class Configuration
     def initialize
       @values = {}
       @values[:client_id] = ENV['CLIENT_ID']
     end
     
     def client_id
       @values[:client_id]
     end
   end
   
   config = Configuration.new
   ```

## Environment Variable Management Tools

### Using dotenv for Development

```ruby
# Install dotenv gem
# gem install dotenv

# Create a .env file in your project root
# CLIENT_ID=your-client-id
# CLIENT_SECRET=your-client-secret

# In your application:
require 'dotenv'
Dotenv.load

# Now ENV['CLIENT_ID'] is available
```

### Using Encrypted Environment Variables

```ruby
# For sensitive production data, consider encrypted environment files
# Example using rails-encrypted-attributes:

# Install the gem
# gem install rails-encrypted-attributes

require 'rails-encrypted-attributes'

# Set up encryption
encryptor = RailsEncrypted::Encryptor.new(
  key: ENV['ENCRYPTION_KEY'],
  salt: 'adk-ruby-auth'
)

# Encrypt environment variable values
encrypted_value = encryptor.encrypt(ENV['CLIENT_SECRET'])
puts "Encrypted value: #{encrypted_value}"

# Decrypt when needed
decrypted_value = encryptor.decrypt(encrypted_value)
```

### Environment Variable Validation

Validate required environment variables at startup:

```ruby
# Create an environment variable validator
class EnvironmentValidator
  REQUIRED_VARIABLES = {
    oauth2: ['CLIENT_ID', 'CLIENT_SECRET'],
    api_key: ['API_KEY'],
    service_account: ['SERVICE_ACCOUNT_JSON']
  }
  
  def self.validate!(auth_type)
    required = REQUIRED_VARIABLES[auth_type.to_sym]
    return unless required
    
    missing = required.select { |var| ENV[var].nil? }
    if missing.any?
      raise "Missing required environment variables for #{auth_type}: #{missing.join(', ')}"
    end
  end
end

# Usage
auth_type = :oauth2
EnvironmentValidator.validate!(auth_type)
```

## Environment Variable Security

### Protecting Environment Variables

Environment variables can be exposed in various ways. Protect them by:

1. **Avoiding Debug Output**
   ```ruby
   # Don't log sensitive environment variables
   
   # Avoid:
   puts "ENV dump: #{ENV.inspect}"
   
   # Instead, log only non-sensitive variables or mask sensitive ones:
   def safe_env_dump
     safe_env = ENV.to_h.dup
     %w(CLIENT_SECRET API_KEY PRIVATE_KEY PASSWORD).each do |pattern|
       safe_env.each do |key, value|
         if key.include?(pattern)
           safe_env[key] = "[REDACTED]"
         end
       end
     end
     safe_env
   end
   
   puts "Safe ENV dump: #{safe_env_dump.inspect}"
   ```

2. **Sanitizing Error Messages**
   ```ruby
   # Sanitize error messages that might contain environment variables
   
   begin
     # Some code that might raise an error with sensitive data
   rescue => e
     # Sanitize error message before logging
     error_message = e.message
     %w(CLIENT_SECRET API_KEY PRIVATE_KEY PASSWORD).each do |pattern|
       ENV.each do |key, value|
         if key.include?(pattern) && value && !value.empty?
           error_message = error_message.gsub(value, "[REDACTED]")
         end
       end
     end
     
     logger.error "Error: #{error_message}"
   end
   ```

3. **Restricting Environment Variable Access**
   ```ruby
   # Restrict access to environment variables using a wrapper
   
   class SecureEnv
     def self.get(name)
       # Implement access control or auditing here
       ENV[name]
     end
   end
   
   # Usage
   client_id = SecureEnv.get('CLIENT_ID')
   ```

## Provider-Specific Environment Variables

### Google Cloud

```bash
# Google OAuth2
export GOOGLE_CLIENT_ID="your-client-id"
export GOOGLE_CLIENT_SECRET="your-client-secret"

# Google Service Account
export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account-key.json"
```

### Microsoft Azure

```bash
# Azure OAuth2/OIDC
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export AZURE_TENANT_ID="your-tenant-id"

# Azure Service Principal
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
```

### AWS

```bash
# AWS credentials
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_SESSION_TOKEN="your-session-token"
export AWS_REGION="us-west-2"
```

## Troubleshooting Tools

### Environment Variable Inspector

Create a simple tool to inspect environment variables:

```ruby
# Save this as env_inspector.rb
#!/usr/bin/env ruby

require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: env_inspector.rb [options]"
  
  opts.on("-v", "--var NAME", "Check a specific environment variable") do |v|
    options[:var] = v
  end
  
  opts.on("-p", "--pattern PATTERN", "Check variables matching a pattern") do |p|
    options[:pattern] = p
  end
  
  opts.on("-l", "--list", "List all environment variables (values redacted)") do
    options[:list] = true
  end
end.parse!

if options[:var]
  var = options[:var]
  puts "Environment variable: #{var}"
  if ENV[var]
    puts "  Value is set (#{ENV[var].length} characters)"
    if var.upcase.include?("SECRET") || var.upcase.include?("KEY") || var.upcase.include?("PASSWORD")
      puts "  Value: [REDACTED]"
    else
      puts "  Value: #{ENV[var]}"
    end
  else
    puts "  NOT SET"
    similar = ENV.keys.select { |k| k.match(/#{var}/i) }
    if similar.any?
      puts "  Similar variables: #{similar.join(', ')}"
    end
  end
elsif options[:pattern]
  pattern = options[:pattern]
  matches = ENV.keys.select { |k| k.match(/#{pattern}/i) }
  puts "Variables matching pattern '#{pattern}':"
  if matches.any?
    matches.each do |var|
      puts "  #{var}: #{var.upcase.include?('SECRET') || var.upcase.include?('KEY') || var.upcase.include?('PASSWORD') ? '[REDACTED]' : ENV[var]}"
    end
  else
    puts "  No matches found"
  end
elsif options[:list]
  puts "All environment variables:"
  ENV.each do |key, value|
    if key.upcase.include?("SECRET") || key.upcase.include?("KEY") || key.upcase.include?("PASSWORD")
      puts "  #{key}: [REDACTED]"
    else
      puts "  #{key}: #{value}"
    end
  end
else
  puts "No options specified. Use --help for usage information."
end
```

Usage:

```bash
# Check a specific variable
ruby env_inspector.rb --var CLIENT_ID

# Check variables matching a pattern
ruby env_inspector.rb --pattern GOOGLE

# List all variables (with sensitive values redacted)
ruby env_inspector.rb --list
```

## Next Steps

- [Credential Storage Issues](./credential_storage.md): For issues with storing credentials
- [Token Lifecycle Management](../guides/token_lifecycle.md): Advanced token management techniques
- [OAuth2 Troubleshooting](./oauth2_issues.md): For OAuth2-specific authentication issues 