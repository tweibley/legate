#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of using the Excon middleware for authentication
# 
# This example demonstrates how to use the ADK::Auth::ExconMiddleware to automatically
# handle authentication for HTTP requests, including automatic token refresh and retry.
#
# Usage:
#   ruby examples/auth/excon_middleware.rb

require 'bundler/setup'
require 'adk'
require 'json'
require 'excon'

puts "ADK::Auth Excon Middleware Example"
puts "--------------------------------"

# Create a basic token store
token_store = ADK::Auth::TokenStore.new

# 1. Example with API Key Authentication
puts "\n1. API Key Authentication Example:"

# Create a middleware using the factory
api_key_middleware = ADK::Auth::MiddlewareFactory.create_api_key(
  api_key: 'test-api-key',
  location: :header,
  name: 'X-API-Key',
  token_store: token_store
)

# Configure a connection with the middleware (long form)
connection = Excon.new('https://httpbin.org')
connection.data[:middlewares] ||= connection.data[:middlewares].dup
connection.data[:middlewares] << ADK::Auth::ExconMiddleware unless connection.data[:middlewares].include?(ADK::Auth::ExconMiddleware)
connection.data[:auth_middleware] = api_key_middleware

# Make a request - the middleware will automatically add the API key header
begin
  response = connection.request(method: :get, path: '/headers')
  
  puts "Request Headers:"
  headers = JSON.parse(response.body)['headers']
  puts "  X-API-Key: #{headers['X-Api-Key']}"
rescue => e
  puts "Error: #{e.message}"
end

# 2. Example with Bearer Token Authentication
puts "\n2. Bearer Token Authentication Example:"

# Use the convenience method from ADK::Auth
begin
  connection = ADK::Auth.create_bearer_connection(
    'https://httpbin.org',
    token: 'test-bearer-token',
    token_store: token_store
  )
  
  # Make sure the middleware is added to the connection's middlewares
  unless connection.data[:middlewares].include?(ADK::Auth::ExconMiddleware)
    connection.data[:middlewares] << ADK::Auth::ExconMiddleware
  end
  
  response = connection.request(method: :get, path: '/headers')
  
  puts "Request Headers:"
  headers = JSON.parse(response.body)['headers']
  puts "  Authorization: #{headers['Authorization']}"
rescue => e
  puts "Error: #{e.message}"
end

# 3. Example with OAuth2 Client Credentials (simulation)
puts "\n3. OAuth2 Client Credentials Example (Simulated):"

# In a real scenario, this would communicate with an actual OAuth2 server
# For this example, we'll use a mock
class MockOAuth2Scheme < ADK::Auth::Scheme
  def scheme_type
    :oauth2
  end
  
  def supports_exchange?
    true
  end
  
  def supports_refresh?
    true
  end
  
  def exchange_token(credential)
    # Simulate token exchange
    ADK::Auth::ExchangedCredential.new(
      auth_type: :oauth2,
      access_token: "mock-access-token-#{rand(1000)}",
      refresh_token: "mock-refresh-token-#{rand(1000)}",
      expires_at: Time.now + 3600,
      scope: 'read write'
    )
  end
  
  def refresh_token(token, credential)
    # Simulate token refresh
    ADK::Auth::ExchangedCredential.new(
      auth_type: :oauth2,
      access_token: "mock-refreshed-token-#{rand(1000)}",
      refresh_token: token.refresh_token,
      expires_at: Time.now + 3600,
      scope: token.scope
    )
  end
  
  def apply_to_request(request, credential)
    # Apply the token to the request
    request[:headers] ||= {}
    
    if credential.is_a?(ADK::Auth::ExchangedCredential) && credential.access_token
      request[:headers]['Authorization'] = "Bearer #{credential.access_token}"
    end
    
    request
  end
end

begin
  # Create the scheme and credential
  oauth2_scheme = MockOAuth2Scheme.new
  oauth2_credential = ADK::Auth::Credential.new(
    auth_type: :oauth2,
    client_id: 'test-client-id',
    client_secret: 'test-client-secret'
  )
  
  # Create a connection using the middleware factory
  connection = ADK::Auth.create_connection(
    'https://httpbin.org',
    scheme: oauth2_scheme,
    credential: oauth2_credential,
    token_store: token_store,
    auto_retry: true,
    max_retries: 2,
    backoff_strategy: :exponential,
    backoff_factor: 0.5
  )
  
  # Make sure the middleware is added to the connection's middlewares
  unless connection.data[:middlewares].include?(ADK::Auth::ExconMiddleware)
    connection.data[:middlewares] << ADK::Auth::ExconMiddleware
  end
  
  # Make a request - middleware will handle token exchange and apply the token
  response = connection.request(method: :get, path: '/headers')
  
  puts "Request Headers:"
  headers = JSON.parse(response.body)['headers']
  puts "  Authorization: #{headers['Authorization']}"
  
  # Demonstrate token refresh by forcing another request
  # In a real scenario, this would happen automatically when a token expires
  puts "\nForcing token refresh and making another request:"
  token = token_store.get(ADK::Auth::ToolIntegration.generate_cache_key(oauth2_scheme, oauth2_credential))
  token_store.clear(ADK::Auth::ToolIntegration.generate_cache_key(oauth2_scheme, oauth2_credential))
  
  # Make another request - middleware should get a new token
  response = connection.request(method: :get, path: '/headers')
  
  puts "Request Headers (after refresh):"
  headers = JSON.parse(response.body)['headers']
  puts "  Authorization: #{headers['Authorization']}"
rescue => e
  puts "Error: #{e.message}"
end

# 4. Example with automatic retry on auth failure (simulation)
puts "\n4. Authentication Failure and Retry Example (Simulated):"

class MockRetryAuthScheme < ADK::Auth::Scheme
  def initialize
    @fail_next = true
  end
  
  def scheme_type
    :custom
  end
  
  def apply_to_request(request, credential)
    request[:headers] ||= {}
    
    if @fail_next
      # This will cause a 401 response
      request[:headers]['X-Should-Fail'] = 'true'
      @fail_next = false
    else
      # This will succeed
      request[:headers]['X-Auth-Success'] = 'true'
    end
    
    request
  end
end

begin
  # Create a simple middleware for the retry test
  retry_scheme = MockRetryAuthScheme.new
  retry_credential = ADK::Auth::Credential.new(auth_type: :custom)
  
  # Create a middleware that will automatically retry on auth failure
  retry_middleware = ADK::Auth::MiddlewareFactory.create(
    scheme: retry_scheme,
    credential: retry_credential,
    auto_retry: true,
    max_retries: 1
  )
  
  # Set up a connection with our middleware
  connection = Excon.new('https://httpbin.org')
  connection.data[:middlewares] ||= connection.data[:middlewares].dup
  connection.data[:middlewares] << ADK::Auth::ExconMiddleware unless connection.data[:middlewares].include?(ADK::Auth::ExconMiddleware)
  connection.data[:auth_middleware] = retry_middleware
  
  # Use a stub to simulate a 401 response followed by success
  Excon.stub({}) do |params|
    if params[:headers] && params[:headers]['X-Should-Fail'] == 'true'
      # Simulate an authentication failure
      {
        status: 401,
        body: '{"error": "Unauthorized"}'
      }
    else
      # Simulate success
      {
        status: 200,
        body: '{"status": "success"}'
      }
    end
  end
  
  # Make a request that will fail and then retry automatically
  puts "Making request that will fail authentication and automatically retry:"
  response = connection.request(method: :get, path: '/anything')
  
  puts "Final response status: #{response[:status]}"
  puts "Response body: #{response[:body]}"
  
  # Clean up stubs
  Excon.stubs.clear
rescue => e
  puts "Error: #{e.message}"
  Excon.stubs.clear
end

puts "\nExample complete." 