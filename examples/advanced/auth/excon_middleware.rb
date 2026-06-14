#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of using the Excon middleware for authentication
#
# This example demonstrates how to use the Legate::Auth::ExconMiddleware to automatically
# handle authentication for HTTP requests, including automatic token refresh and retry.
#
# Usage:
#   ruby examples/advanced/auth/excon_middleware.rb

require 'bundler/setup'
require 'legate'
require 'json'
require 'excon'

puts 'Legate::Auth Excon Middleware Example'
puts '--------------------------------'

# Create a basic token store
token_store = Legate::Auth::TokenStore.new

# Enable mock mode for Excon to simulate HTTP requests
Excon.defaults[:mock] = true

# 1. Example with API Key Authentication
puts "\n1. API Key Authentication Example:"

# Set up our mock response for API Key authentication
Excon.stub({}) do |params|
  if params[:headers] && params[:headers]['X-API-Key'] == 'test-api-key'
    {
      status: 200,
      body: JSON.generate({
                            headers: params[:headers]
                          })
    }
  else
    { status: 401, body: '{"error": "Unauthorized"}' }
  end
end

# Create a middleware using the factory
api_key_middleware = Legate::Auth::MiddlewareFactory.create_api_key(
  api_key: 'test-api-key',
  location: :header,
  name: 'X-API-Key',
  token_store: token_store
)

# Create a connection with the middleware properly configured
connection = Excon.new('https://httpbin.org')

# Add our middleware to the stack if not already present
connection.data[:middlewares] = connection.data[:middlewares].dup
connection.data[:middlewares] << Legate::Auth::ExconMiddleware unless connection.data[:middlewares].include?(Legate::Auth::ExconMiddleware)

# Set our configured middleware instance
connection.data[:auth_middleware] = api_key_middleware

# Make a request - the middleware will automatically add the API key header
begin
  response = connection.request(method: :get, path: '/headers')

  puts 'Request Headers:'
  headers = JSON.parse(response.body)['headers']
  puts "  X-API-Key: #{headers['X-Api-Key'] || headers['X-API-Key']}"
rescue StandardError => e
  puts "Error: #{e.message}"
end

# 2. Example with Bearer Token Authentication
puts "\n2. Bearer Token Authentication Example:"

# Set up our mock response for Bearer authentication
Excon.stub({}) do |params|
  if params[:headers] && params[:headers]['Authorization'] == 'Bearer test-bearer-token'
    {
      status: 200,
      body: JSON.generate({
                            headers: params[:headers]
                          })
    }
  else
    { status: 401, body: '{"error": "Unauthorized"}' }
  end
end

# Create a connection with bearer token middleware
connection = Excon.new('https://httpbin.org')
bearer_middleware = Legate::Auth::MiddlewareFactory.create_bearer(
  token: 'test-bearer-token',
  token_store: token_store
)

# Configure the connection to use our middleware
connection.data[:middlewares] = connection.data[:middlewares].dup
connection.data[:middlewares] << Legate::Auth::ExconMiddleware unless connection.data[:middlewares].include?(Legate::Auth::ExconMiddleware)
connection.data[:auth_middleware] = bearer_middleware

# Make a request with bearer authentication
begin
  response = connection.request(method: :get, path: '/headers')

  puts 'Request Headers:'
  headers = JSON.parse(response.body)['headers']
  puts "  Authorization: #{headers['Authorization']}"
rescue StandardError => e
  puts "Error: #{e.message}"
end

# 3. Example with OAuth2 Client Credentials (simulation)
puts "\n3. OAuth2 Client Credentials Example (Simulated):"

# In a real scenario, this would communicate with an actual OAuth2 server
# For this example, we'll use a mock
class MockOAuth2Scheme < Legate::Auth::Scheme
  def scheme_type
    :oauth2
  end

  def supports_exchange?
    true
  end

  def supports_refresh?
    true
  end

  def exchange_token(_credential)
    # Simulate token exchange
    Legate::Auth::ExchangedCredential.new(
      auth_type: :oauth2,
      access_token: "mock-access-token-#{rand(1000)}",
      refresh_token: "mock-refresh-token-#{rand(1000)}",
      expires_at: Time.now + 3600,
      scope: 'read write'
    )
  end

  def refresh_token(token, _credential)
    # Simulate token refresh
    Legate::Auth::ExchangedCredential.new(
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

    request[:headers]['Authorization'] = "Bearer #{credential.access_token}" if credential.is_a?(Legate::Auth::ExchangedCredential) && credential.access_token

    request
  end
end

# Set up stub for OAuth2 authentication to capture any Bearer token
Excon.stub({}) do |params|
  if params[:headers] && params[:headers]['Authorization'] && params[:headers]['Authorization'].start_with?('Bearer ')
    {
      status: 200,
      body: JSON.generate({
                            headers: params[:headers]
                          })
    }
  else
    { status: 401, body: '{"error": "Unauthorized"}' }
  end
end

begin
  # Create the scheme and credential
  oauth2_scheme = MockOAuth2Scheme.new
  oauth2_credential = Legate::Auth::Credential.new(
    auth_type: :oauth2,
    client_id: 'test-client-id',
    client_secret: 'test-client-secret'
  )

  # Create a connection
  connection = Excon.new('https://httpbin.org')

  # Create the middleware instance
  oauth2_middleware = Legate::Auth::ExconMiddleware.new(
    nil,
    scheme: oauth2_scheme,
    credential: oauth2_credential,
    token_store: token_store,
    auto_retry: true,
    max_retries: 2,
    backoff_strategy: :exponential,
    backoff_factor: 0.5
  )

  # Properly configure the connection
  connection.data[:middlewares] = connection.data[:middlewares].dup
  connection.data[:middlewares] << Legate::Auth::ExconMiddleware unless connection.data[:middlewares].include?(Legate::Auth::ExconMiddleware)
  connection.data[:auth_middleware] = oauth2_middleware

  # Make a request - middleware will handle token exchange and apply the token
  response = connection.request(method: :get, path: '/headers')

  puts 'Request Headers:'
  headers = JSON.parse(response.body)['headers']
  puts "  Authorization: #{headers['Authorization']}"

  # Demonstrate token refresh by forcing another request
  # In a real scenario, this would happen automatically when a token expires
  puts "\nForcing token refresh and making another request:"
  token = token_store.get(Legate::Auth::ToolIntegration.generate_cache_key(oauth2_scheme, oauth2_credential))
  token_store.clear(Legate::Auth::ToolIntegration.generate_cache_key(oauth2_scheme, oauth2_credential))

  # Make another request - middleware should get a new token
  response = connection.request(method: :get, path: '/headers')

  puts 'Request Headers (after refresh):'
  headers = JSON.parse(response.body)['headers']
  puts "  Authorization: #{headers['Authorization']}"
rescue StandardError => e
  puts "Error: #{e.message}"
end

# 4. Example with automatic retry on auth failure (simulation)
puts "\n4. Authentication Failure and Retry Example (Simulated):"

class MockRetryAuthScheme < Legate::Auth::Scheme
  def initialize
    @fail_count = 1 # Fail the first request, then succeed
  end

  def scheme_type
    :custom
  end

  def apply_to_request(request, _credential)
    request[:headers] ||= {}

    if @fail_count > 0
      @fail_count -= 1
      # This will cause a 401 response
      request[:headers]['X-Should-Fail'] = 'true'
    else
      # This will succeed
      request[:headers]['X-Auth-Success'] = 'true'
    end

    request
  end
end

begin
  # Set up stubs for retry test
  Excon.stub({}) do |params|
    if params[:headers] && params[:headers]['X-Should-Fail'] == 'true'
      # Simulate an authentication failure
      {
        status: 401,
        body: '{"error": "Unauthorized"}'
      }
    elsif params[:headers] && params[:headers]['X-Auth-Success'] == 'true'
      # Simulate success after retry
      {
        status: 200,
        body: JSON.generate({
                              status: 'success',
                              headers: params[:headers]
                            })
      }
    else
      # Default response
      {
        status: 400,
        body: '{"error": "Bad Request"}'
      }
    end
  end

  # Create a simple middleware for the retry test
  retry_scheme = MockRetryAuthScheme.new
  retry_credential = Legate::Auth::Credential.new(auth_type: :custom)

  # Create a middleware that will automatically retry on auth failure
  retry_middleware = Legate::Auth::ExconMiddleware.new(
    nil,
    scheme: retry_scheme,
    credential: retry_credential,
    auto_retry: true,
    max_retries: 1
  )

  # Set up a connection with our middleware
  connection = Excon.new('https://httpbin.org')
  connection.data[:middlewares] = connection.data[:middlewares].dup
  connection.data[:middlewares] << Legate::Auth::ExconMiddleware unless connection.data[:middlewares].include?(Legate::Auth::ExconMiddleware)
  connection.data[:auth_middleware] = retry_middleware

  # Make a request that will fail and then retry automatically
  puts 'Making request that will fail authentication and automatically retry:'
  response = connection.request(method: :get, path: '/anything')

  response_data = JSON.parse(response.body)
  puts "Final response status: #{response.status}"
  puts "Response contains X-Auth-Success header: #{!response_data['headers']['X-Auth-Success'].nil?}"

  # Clean up stubs
  Excon.stubs.clear
rescue StandardError => e
  puts "Error: #{e.message}"
  Excon.stubs.clear
end

puts "\nExample complete."
