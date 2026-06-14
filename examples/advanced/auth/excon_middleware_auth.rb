#!/usr/bin/env ruby
# frozen_string_literal: true

# Enhanced Example of using the Excon middleware for authentication
#
# This example demonstrates how to use the Legate::Auth::ExconMiddleware with various
# authentication schemes, including automatic token refresh, retry functionality,
# and configurable backoff strategies.
#
# Usage:
#   ruby examples/advanced/auth/excon_middleware_auth.rb

require 'bundler/setup'
require 'legate'
require 'json'
require 'excon'

puts 'Legate::Auth Enhanced Excon Middleware Example'
puts '----------------------------------------'

# Initialize a session service and token store
session_service = Legate::SessionService::Memory.new
token_store = Legate::Auth::TokenStore.new(session_service)

# 1. Example with API Key Authentication
puts "\n1. API Key Authentication Example:"

begin
  # Create a connection using the convenience method
  connection = Legate::Auth.create_api_key_connection(
    'https://httpbin.org',
    api_key: 'test-api-key-1234',
    location: 'header',
    name: 'X-API-Key',
    token_store: token_store,
    auto_retry: true,
    max_retries: 2,
    backoff_strategy: :exponential,
    backoff_factor: 0.5
  )

  # Make sure the middleware is added to the connection's middlewares
  connection.data[:middlewares] << Legate::Auth::ExconMiddleware unless connection.data[:middlewares].include?(Legate::Auth::ExconMiddleware)

  # Make a request - the middleware will automatically add the API key header
  response = connection.request(method: :get, path: '/headers')

  puts 'Request Headers:'
  headers = JSON.parse(response.body)['headers']
  puts "  X-API-Key: #{headers['X-Api-Key']}"
rescue StandardError => e
  puts "Error: #{e.message}"
end

# 2. Example with Bearer Token Authentication
puts "\n2. Bearer Token Authentication Example:"

begin
  # Create a connection using the convenience method
  connection = Legate::Auth.create_bearer_connection(
    'https://httpbin.org',
    token: 'test-bearer-token-5678',
    token_store: token_store,
    auto_retry: true,
    max_retries: 2,
    backoff_strategy: :jitter, # Use jitter backoff to prevent thundering herd
    backoff_factor: 0.5
  )

  # Make sure the middleware is added to the connection's middlewares
  connection.data[:middlewares] << Legate::Auth::ExconMiddleware unless connection.data[:middlewares].include?(Legate::Auth::ExconMiddleware)

  # Make a request - the middleware will automatically add the Bearer token
  response = connection.request(method: :get, path: '/headers')

  puts 'Request Headers:'
  headers = JSON.parse(response.body)['headers']
  puts "  Authorization: #{headers['Authorization']}"
rescue StandardError => e
  puts "Error: #{e.message}"
end

# 3. Example with Basic Authentication
puts "\n3. Basic Authentication Example:"

begin
  # Create a connection using the convenience method
  connection = Legate::Auth.create_basic_auth_connection(
    'https://httpbin.org',
    username: 'testuser',
    password: 'testpassword',
    token_store: token_store,
    auto_retry: true,
    max_retries: 3,
    backoff_strategy: :linear,
    backoff_factor: 1.0
  )

  # Make sure the middleware is added to the connection's middlewares
  connection.data[:middlewares] << Legate::Auth::ExconMiddleware unless connection.data[:middlewares].include?(Legate::Auth::ExconMiddleware)

  # Make a request - the middleware will automatically add the Basic Auth header
  response = connection.request(method: :get, path: '/headers')

  puts 'Request Headers:'
  headers = JSON.parse(response.body)['headers']
  puts "  Authorization: #{headers['Authorization']}"
rescue StandardError => e
  puts "Error: #{e.message}"
end

# 4. Example with OAuth2 Client Credentials (simulation)
puts "\n4. OAuth2 Client Credentials Example (Simulated):"

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
      expires_at: Time.now + 10, # Short expiry for testing refresh
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

    if credential.is_a?(Legate::Auth::ExchangedCredential) && credential.access_token
      request[:headers]['Authorization'] = "Bearer #{credential.access_token}"
    elsif credential[:client_id] && credential[:client_secret]
      # If we don't have a token yet but have client credentials, we could
      # apply client auth here (in a real implementation)
      basic_auth = Base64.strict_encode64("#{credential[:client_id]}:#{credential[:client_secret]}")
      request[:headers]['Authorization'] = "Basic #{basic_auth}"
    end

    request
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

  # Create a connection using the middleware factory
  connection = Legate::Auth.create_connection(
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
  connection.data[:middlewares] << Legate::Auth::ExconMiddleware unless connection.data[:middlewares].include?(Legate::Auth::ExconMiddleware)

  # Make a request - middleware will handle token exchange and apply the token
  response = connection.request(method: :get, path: '/headers')

  puts 'Request Headers:'
  headers = JSON.parse(response.body)['headers']
  puts "  Authorization: #{headers['Authorization']}"

  # Wait for token to expire
  puts "\nWaiting for token to expire (10 seconds)..."
  sleep 11

  # Make another request - middleware should refresh the token
  response = connection.request(method: :get, path: '/headers')

  puts 'Request Headers (after refresh):'
  headers = JSON.parse(response.body)['headers']
  puts "  Authorization: #{headers['Authorization']}"
rescue StandardError => e
  puts "Error: #{e.message}"
end

# 5. Example with automatic retry on auth failure (simulation)
puts "\n5. Authentication Failure and Retry Example (Simulated):"

class RetryCounterScheme < Legate::Auth::Scheme
  def initialize
    @attempts = 0
    @max_failures = 2
  end

  def scheme_type
    :custom
  end

  def apply_to_request(request, _credential)
    request[:headers] ||= {}

    @attempts += 1

    if @attempts <= @max_failures
      # This will cause a 401 response for the first N attempts
      request[:headers]['X-Should-Fail'] = 'true'
      request[:headers]['X-Attempt'] = @attempts.to_s
    else
      # This will succeed
      request[:headers]['X-Auth-Success'] = 'true'
      request[:headers]['X-Attempt'] = @attempts.to_s
    end

    request
  end
end

begin
  # Create a scheme that will fail a certain number of times
  retry_scheme = RetryCounterScheme.new
  retry_credential = Legate::Auth::Credential.new(auth_type: :custom)

  # Create a middleware that will automatically retry on auth failure
  retry_middleware = Legate::Auth::MiddlewareFactory.create(
    scheme: retry_scheme,
    credential: retry_credential,
    auto_retry: true,
    max_retries: 3,
    backoff_strategy: :exponential,
    backoff_factor: 0.1 # Small factor to make test run quickly
  )

  # Set up a connection with our middleware
  connection = Excon.new('https://httpbin.org')
  connection.data[:middlewares] ||= connection.data[:middlewares].dup
  connection.data[:middlewares] << Legate::Auth::ExconMiddleware unless connection.data[:middlewares].include?(Legate::Auth::ExconMiddleware)
  connection.data[:auth_middleware] = retry_middleware

  # Use a stub to simulate a 401 response followed by success
  Excon.stub({}) do |params|
    if params[:headers] && params[:headers]['X-Should-Fail'] == 'true'
      # Log the attempt
      attempt = params[:headers]['X-Attempt']
      puts "Request attempt #{attempt} - Authentication failed"

      # Simulate an authentication failure
      {
        status: 401,
        body: "{\"error\": \"Unauthorized\", \"attempt\": #{attempt}}"
      }
    else
      # Log the successful attempt
      attempt = params[:headers]['X-Attempt']
      puts "Request attempt #{attempt} - Authentication succeeded"

      # Simulate success
      {
        status: 200,
        body: "{\"status\": \"success\", \"attempt\": #{attempt}}"
      }
    end
  end

  # Make a request that will fail and then retry automatically
  puts 'Making request that will fail authentication and retry automatically:'
  response = connection.request(method: :get, path: '/anything')

  puts "Final response status: #{response[:status]}"
  puts "Response body: #{response[:body]}"

  # Clean up stubs
  Excon.stubs.clear
rescue StandardError => e
  puts "Error: #{e.message}"
  Excon.stubs.clear
end

# 6. Example with retry on rate limiting (simulation)
puts "\n6. Rate Limiting and Retry Example (Simulated):"

class RateLimitScheme < Legate::Auth::Scheme
  def initialize
    @attempts = 0
    @rate_limit_count = 2 # Will hit rate limit twice before succeeding
  end

  def scheme_type
    :custom
  end

  def apply_to_request(request, _credential)
    request[:headers] ||= {}

    @attempts += 1
    request[:headers]['X-Attempt'] = @attempts.to_s

    request[:headers]['X-Rate-Limited'] = if @attempts <= @rate_limit_count
                                            # This will trigger rate limiting
                                            'true'
                                          else
                                            # This will succeed
                                            'false'
                                          end

    request
  end
end

begin
  # Create a scheme that will trigger rate limiting
  rate_limit_scheme = RateLimitScheme.new
  rate_limit_credential = Legate::Auth::Credential.new(auth_type: :custom)

  # Create a middleware that will handle rate limiting
  rate_limit_middleware = Legate::Auth::MiddlewareFactory.create(
    scheme: rate_limit_scheme,
    credential: rate_limit_credential,
    auto_retry: true,
    max_retries: 5,
    backoff_strategy: :fibonacci, # Use fibonacci backoff for rate limiting
    backoff_factor: 0.1, # Small factor to make test run quickly
    retry_on: [429] # Explicitly retry on 429 Too Many Requests
  )

  # Set up a connection with our middleware
  connection = Excon.new('https://httpbin.org')
  connection.data[:middlewares] ||= connection.data[:middlewares].dup
  connection.data[:middlewares] << Legate::Auth::ExconMiddleware unless connection.data[:middlewares].include?(Legate::Auth::ExconMiddleware)
  connection.data[:auth_middleware] = rate_limit_middleware

  # Use a stub to simulate rate limiting
  Excon.stub({}) do |params|
    if params[:headers] && params[:headers]['X-Rate-Limited'] == 'true'
      # Log the attempt
      attempt = params[:headers]['X-Attempt']
      puts "Request attempt #{attempt} - Rate limited"

      # Simulate rate limiting with Retry-After header
      {
        status: 429,
        headers: { 'Retry-After' => '1' }, # Suggest a 1 second retry time
        body: "{\"error\": \"Too Many Requests\", \"attempt\": #{attempt}}"
      }
    else
      # Log the successful attempt
      attempt = params[:headers]['X-Attempt']
      puts "Request attempt #{attempt} - Request succeeded"

      # Simulate success
      {
        status: 200,
        body: "{\"status\": \"success\", \"attempt\": #{attempt}}"
      }
    end
  end

  # Make a request that will be rate limited and then retry automatically
  puts 'Making request that will be rate limited and retry automatically:'
  response = connection.request(method: :get, path: '/anything')

  puts "Final response status: #{response[:status]}"
  puts "Response body: #{response[:body]}"

  # Clean up stubs
  Excon.stubs.clear
rescue StandardError => e
  puts "Error: #{e.message}"
  Excon.stubs.clear
end

puts "\nExample complete."
