#!/usr/bin/env ruby
# frozen_string_literal: true

# Token Lifecycle Management Example
#
# This example demonstrates comprehensive token lifecycle management including:
# - Token acquisition and storage
# - Automatic token refresh on expiration
# - Token invalidation and error handling
# - Manual token management operations
# - Integration with different authentication schemes
#
# Usage:
#   ruby examples/advanced/auth/token_lifecycle_example.rb [--scheme oauth2|service_account] [--demo-mode]

require 'bundler/setup'
require 'legate'
require 'legate/auth'
require 'legate/auth/token_manager'
require 'legate/auth/token_store'
require 'optparse'
require 'json'
require 'time'

# Helper method to get auth-related keys from the session service
def get_auth_keys(session_service)
  if session_service.respond_to?(:scoped_states)
    # For InMemory session service, check the scoped_states directly
    session_service.scoped_states.keys.select { |key| key.start_with?('auth:') }

  elsif session_service.respond_to?(:keys)
    # For Redis-based session service
    session_service.keys('auth:*')
  else
    []
  end
end

# Parse command line options
options = {
  scheme: 'oauth2',
  demo_mode: false,
  verbose: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{__FILE__} [options]"

  opts.on('--scheme SCHEME', %w[oauth2 service_account], 'Authentication scheme to demonstrate (oauth2, service_account)') do |scheme|
    options[:scheme] = scheme
  end

  opts.on('--demo-mode', 'Run in demo mode with simulated tokens') do
    options[:demo_mode] = true
  end

  opts.on('--verbose', 'Enable verbose output') do
    options[:verbose] = true
  end

  opts.on('--help', 'Show this help') do
    puts opts
    exit
  end
end.parse!

puts '=== Token Lifecycle Management Example ==='
puts "Scheme: #{options[:scheme]}"
puts "Demo Mode: #{options[:demo_mode] ? 'enabled' : 'disabled'}"
puts

# Setup session service for token storage
session_service = Legate::SessionService::InMemory.new
puts '✓ Session service initialized'

# Create token store for persistent token management
token_store = Legate::Auth::TokenStore.new(session_service)
puts '✓ Token store created'

# Create token manager for automatic lifecycle management
token_manager = Legate::Auth::TokenManager.new(token_store)
puts '✓ Token manager initialized'

# Configure callbacks for token lifecycle events
token_manager.on(:before_expiry) do |event|
  puts "⏰ Token approaching expiration: #{event[:token]&.access_token&.[](0..15)}..."
end

token_manager.on(:refresh_success) do |event|
  expires_in = event[:token]&.expires_at ? (event[:token].expires_at - Time.now).to_i : 0
  puts "🔄 Token refreshed successfully: #{event[:token]&.access_token&.[](0..15)}... (expires in #{expires_in} seconds)"
end

token_manager.on(:refresh_failure) do |event|
  puts "⚠️ Token refresh failed: #{event[:error]&.message || 'Unknown error'}"
end

token_manager.on(:invalidated) do |event|
  puts "❌ Token invalidated: #{event[:cache_key]}"
end

puts '✓ Token lifecycle callbacks configured'

# Helper method to create credentials and schemes
def create_auth_components(scheme_type, demo_mode: false)
  case scheme_type
  when 'oauth2'
    scheme = if demo_mode
               # Create a mock OAuth2 scheme for demo
               Legate::Auth::Schemes::OAuth2.new(
                 authorization_url: 'https://example.com/oauth/authorize',
                 token_url: 'https://example.com/oauth/token',
                 scopes: %w[read write]
               )
             else
               Legate::Auth::Schemes::OAuth2.new(
                 authorization_url: ENV['OAUTH_AUTH_URL'] || 'https://accounts.google.com/o/oauth2/auth',
                 token_url: ENV['OAUTH_TOKEN_URL'] || 'https://oauth2.googleapis.com/token',
                 scopes: %w[email profile]
               )
             end

    credential = Legate::Auth::Credential.new(
      auth_type: :oauth2,
      client_id: ENV['OAUTH_CLIENT_ID'] || 'demo-client-id',
      client_secret: ENV['OAUTH_CLIENT_SECRET'] || 'demo-client-secret'
    )

    [scheme, credential]

  when 'service_account'
    # Set test environment for demo mode to skip full validation
    ENV['RSPEC_ENV'] = 'test' if demo_mode

    scheme = Legate::Auth::Schemes::GoogleServiceAccount.new(
      scopes: ['https://www.googleapis.com/auth/cloud-platform']
    )

    if demo_mode
      # Create demo service account credential
      demo_key = {
        'type' => 'service_account',
        'project_id' => 'demo-project',
        'private_key_id' => 'demo-key-id',
        'private_key' => "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC...\n-----END PRIVATE KEY-----\n",
        'client_email' => 'demo@demo-project.iam.gserviceaccount.com',
        'client_id' => '123456789',
        'auth_uri' => 'https://accounts.google.com/o/oauth2/auth',
        'token_uri' => 'https://oauth2.googleapis.com/token'
      }

      credential = Legate::Auth::Credential.new(
        auth_type: :google_service_account,
        service_account_key: demo_key.to_json,
        client_email: demo_key['client_email']
      )
    else
      credential = Legate::Auth::Credential.new(
        auth_type: :google_service_account,
        service_account_key: ENV['SERVICE_ACCOUNT_KEY'] || File.read(ENV['SERVICE_ACCOUNT_KEY_FILE'])
      )
    end

    [scheme, credential]

  else
    raise ArgumentError, "Unsupported scheme: #{scheme_type}"
  end
end

# Helper method to create a demo token for testing
def create_demo_token(scheme_type)
  case scheme_type
  when 'oauth2'
    Legate::Auth::ExchangedCredential.new(
      auth_type: :oauth2,
      access_token: 'demo_access_token_' + SecureRandom.hex(8),
      refresh_token: 'demo_refresh_token_' + SecureRandom.hex(8),
      token_type: 'Bearer',
      expires_at: Time.now + 30,  # Expires in 30 seconds for demo
      scope: 'email profile'
    )
  when 'service_account'
    Legate::Auth::ExchangedCredential.new(
      auth_type: :google_service_account,
      access_token: 'demo_sa_token_' + SecureRandom.hex(8),
      token_type: 'Bearer',
      expires_at: Time.now + 45,  # Expires in 45 seconds for demo
      scope: 'https://www.googleapis.com/auth/cloud-platform'
    )
  end
end

# Create authentication components
begin
  scheme, credential = create_auth_components(options[:scheme], demo_mode: options[:demo_mode])
  puts '✓ Authentication scheme and credential created'
rescue StandardError => e
  puts "❌ Failed to create authentication components: #{e.message}"
  puts "\nTip: Use --demo-mode to run with simulated credentials" unless options[:demo_mode]
  exit 1
end

# Token lifecycle demonstration
puts "\n=== Token Lifecycle Demonstration ==="

token_key = "#{options[:scheme]}_demo_token"

# 1. Initial token acquisition
puts "\n1. Initial Token Acquisition"
puts '─' * 40

if options[:demo_mode]
  # In demo mode, simulate getting a token
  demo_token = create_demo_token(options[:scheme])
  token_store.store(token_key, demo_token)
  current_token = demo_token
  puts '✓ Demo token created and stored'
else
  # In real mode, attempt to get a token through the token manager
  puts 'Attempting to acquire token through token manager...'
  current_token = token_manager.get_token(scheme, credential)

  if current_token
    puts '✓ Token acquired successfully'
  else
    puts '⚠️ Token acquisition failed (this is expected for interactive flows in CLI)'
    puts 'Creating a demo token for lifecycle demonstration...'
    current_token = create_demo_token(options[:scheme])
    token_store.store(token_key, current_token)
  end
end

# Display token information
if current_token
  puts "\nToken Information:"
  puts "  Type: #{current_token.token_type}"
  puts "  Access Token: #{current_token.access_token[0..15]}..."
  puts "  Expires At: #{current_token.expires_at}"
  puts "  Expires In: #{(current_token.expires_at - Time.now).to_i} seconds"
  puts "  Scope: #{current_token[:scope]}" if current_token[:scope]
  puts "  Has Refresh Token: #{current_token.refresh_token ? 'Yes' : 'No'}"
end

# 2. Token retrieval from storage
puts "\n2. Token Retrieval from Storage"
puts '─' * 40

retrieved_token = token_store.get(token_key)
if retrieved_token
  puts '✓ Token successfully retrieved from storage'
  puts "  Retrieved token matches stored token: #{current_token.access_token == retrieved_token.access_token}"
else
  puts '❌ Failed to retrieve token from storage'
end

# 3. Token expiration checking
puts "\n3. Token Expiration Checking"
puts '─' * 40

expires_in_seconds = (current_token.expires_at - Time.now).to_i

puts "Current time: #{Time.now}"
puts "Token expires at: #{current_token.expires_at}"
puts "Token expired?: #{current_token.expired?}"
puts "Token expires in: #{expires_in_seconds} seconds"

if expires_in_seconds > 0
  puts 'Token is currently valid'
else
  puts 'Token has already expired'
end

# 4. Automatic token refresh demonstration
puts "\n4. Automatic Token Refresh"
puts '─' * 40

if current_token.refresh_token && !options[:demo_mode]
  puts 'Token has refresh token - attempting refresh...'

  begin
    refreshed_token = token_manager.refresh_token(scheme, credential, current_token)
    if refreshed_token
      puts '✓ Token refreshed successfully'
      puts "  New access token: #{refreshed_token.access_token[0..15]}..."
      puts "  New expiry: #{refreshed_token.expires_at}"
      current_token = refreshed_token
    else
      puts '⚠️ Token refresh returned nil'
    end
  rescue StandardError => e
    puts "❌ Token refresh failed: #{e.message}"
  end
else
  puts 'Token refresh not available (no refresh token or demo mode)'

  if options[:demo_mode]
    puts 'Simulating token refresh in demo mode...'
    refreshed_demo = create_demo_token(options[:scheme])
    token_store.store(token_key, refreshed_demo)
    puts "✓ Demo token 'refreshed' (new token created)"
    current_token = refreshed_demo
  end
end

# 5. Waiting for expiration (demo)
current_expires_in = (current_token.expires_at - Time.now).to_i
if options[:demo_mode] && current_expires_in > 0 && current_expires_in < 60
  puts "\n5. Waiting for Token Expiration (Demo)"
  puts '─' * 40

  puts "Token expires in #{current_expires_in} seconds"
  puts 'Waiting for expiration... (press Ctrl+C to skip)'

  begin
    sleep_time = [current_expires_in + 1, 5].min # Max 5 seconds wait
    sleep(sleep_time)

    puts 'Checking token status after wait...'
    puts "Token expired?: #{current_token.expired?}"

    # Demonstrate automatic refresh on next access
    puts 'Attempting to get token (should trigger refresh if expired)...'
    fresh_token = token_manager.get_token(scheme, credential, force_refresh: current_token.expired?)

    puts '✓ Automatic refresh triggered on expired token access' if fresh_token && fresh_token.access_token != current_token.access_token
  rescue Interrupt
    puts "\n⏭️ Skipped expiration wait"
  end
end

# 6. Manual token operations
puts "\n6. Manual Token Operations"
puts '─' * 40

# Force refresh
puts 'Force refreshing token...'
if options[:demo_mode]
  new_demo_token = create_demo_token(options[:scheme])
  token_store.store(token_key, new_demo_token)
  puts '✓ Demo token force refreshed'
else
  force_refreshed = token_manager.get_token(scheme, credential, force_refresh: true)
  if force_refreshed
    puts '✓ Token force refreshed'
  else
    puts '⚠️ Force refresh failed'
  end
end

# Check for multiple tokens
puts "\nChecking all stored tokens..."
all_tokens = get_auth_keys(session_service)
puts "Found #{all_tokens.length} authentication-related keys in storage:"
all_tokens.each { |key| puts "  - #{key}" }

# 7. Token invalidation
puts "\n7. Token Invalidation"
puts '─' * 40

puts 'Invalidating token...'
# Generate the proper cache key for the token manager
require_relative '../../../lib/legate/auth/tool_integration'
cache_key = Legate::Auth::ToolIntegration.generate_cache_key(scheme, credential)
token_manager.invalidate_token(cache_key)

# Verify invalidation
invalidated_token = token_store.get(token_key)
if invalidated_token.nil?
  puts '✓ Token successfully invalidated and removed from storage'
else
  puts '⚠️ Token still exists in storage after invalidation'
end

# 8. Error handling demonstration
puts "\n8. Error Handling"
puts '─' * 40

puts 'Attempting to get invalidated token...'
result = token_manager.get_token(scheme, credential)
if result.nil?
  puts '✓ Correctly returned nil for invalidated token'
else
  puts "⚠️ Unexpectedly returned a token: #{result.access_token[0..15]}..."
end

# Try token operations on non-existent token
puts 'Attempting to refresh non-existent token...'
begin
  fake_token = create_demo_token(options[:scheme])
  fake_token.instance_variable_set(:@access_token, 'invalid_token')
  refresh_result = token_manager.refresh_token(scheme, credential, fake_token)
  if refresh_result
    puts '⚠️ Unexpectedly succeeded refreshing invalid token'
  else
    puts '✓ Correctly failed to refresh invalid token'
  end
rescue StandardError => e
  puts "✓ Correctly raised error for invalid token refresh: #{e.class}"
end

# 9. Cleanup demonstration
puts "\n9. Cleanup"
puts '─' * 40

puts 'Clearing all tokens...'
token_store.clear_all
remaining_tokens = get_auth_keys(session_service)
puts "Remaining auth tokens after cleanup: #{remaining_tokens.length}"

if remaining_tokens.empty?
  puts '✓ All tokens successfully cleared'
else
  puts "⚠️ Some tokens remain: #{remaining_tokens}"
end

puts "\n=== Token Lifecycle Demonstration Complete ==="
puts "\nKey concepts demonstrated:"
puts '• Token acquisition and storage'
puts '• Automatic expiration detection'
puts '• Token refresh mechanisms'
puts '• Manual token operations'
puts '• Error handling and recovery'
puts '• Token invalidation and cleanup'
puts '• Event-based lifecycle callbacks'
puts "\nThis example shows how the Legate authentication system handles"
puts 'the complete token lifecycle automatically, with manual override'
puts 'capabilities when needed.'
