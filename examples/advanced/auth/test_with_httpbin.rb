#!/usr/bin/env ruby
# frozen_string_literal: true

# Test with httpbin.org which is more reliable than OpenWeatherMap API
#
# Usage:
#   ruby examples/advanced/auth/test_with_httpbin.rb

require 'bundler/setup'
require 'legate'
require 'legate/auth'
require 'json'
require 'excon'
require 'legate/session_service/in_memory'

# Enable debug mode
ENV['DEBUG'] = 'true'

puts 'Testing Legate::Auth::ExconMiddleware with httpbin.org'
puts '--------------------------------------------'

# Create session service and token store
session_service = Legate::SessionService::InMemory.new
token_store = Legate::Auth::TokenStore.new(session_service)

# Test API Key
API_KEY = 'test-api-key-123'

# Create the ApiKey scheme and credential
api_key_scheme = Legate::Auth::Schemes::ApiKey.new
api_key_credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: API_KEY,
  location: 'query',
  name: 'apikey'
)

puts "\nTest 1: Direct API call with Excon"
puts '-------------------------------'

begin
  # Make a direct Excon request
  url = "https://httpbin.org/get?test=value&apikey=#{API_KEY}"

  puts "Making direct request to: #{url}"

  # Create the connection with normal timeouts
  response = Excon.get(url,
                       connect_timeout: 10,
                       read_timeout: 10,
                       write_timeout: 10)

  puts "Response Status: #{response.status}"

  if response.status == 200
    data = JSON.parse(response.body)
    puts "Data received: #{data['args'].inspect}"
  else
    puts "Error: #{response.status} - #{response.body}"
  end
rescue StandardError => e
  puts "Request Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
end

puts "\nTest 2: Fixed Legate::Auth::ExconMiddleware"
puts '------------------------------------'

begin
  # Create our middleware instance directly
  middleware = Legate::Auth::ExconMiddleware.new(
    nil,
    scheme: api_key_scheme,
    credential: api_key_credential,
    token_store: token_store
  )

  # Create a connection and add our middleware directly
  connection = Excon.new('https://httpbin.org',
                         connect_timeout: 10,
                         read_timeout: 10,
                         write_timeout: 10)

  # Get the default middleware stack
  default_middlewares = connection.data[:middlewares].dup

  # Append our middleware to the stack
  connection.data[:middlewares] = default_middlewares + [Legate::Auth::ExconMiddleware]

  # Store our middleware instance in the connection
  connection.data[:auth_middleware] = middleware

  puts 'Connection created with middleware'
  puts 'Making request with Legate::Auth::ExconMiddleware...'

  # Make the request
  response = connection.request(
    method: :get,
    path: '/get',
    query: {
      test: 'value'
    }
  )

  puts "Response Status: #{response.status}"

  if response.status == 200
    data = JSON.parse(response.body)
    puts "Data received: #{data['args'].inspect}"
  else
    puts "Error: #{response.status} - #{response.body}"
  end
rescue StandardError => e
  puts "Request Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
end

puts "\nTest 3: Using HttpClientUtils.create_connection"
puts '-------------------------------------------'

begin
  # Use the Legate::Auth::HttpClientUtils.create_connection method
  puts 'Creating connection using HttpClientUtils...'

  connection = Legate::Auth::HttpClientUtils.create_connection(
    'https://httpbin.org',
    scheme: api_key_scheme,
    credential: api_key_credential,
    token_store: token_store,
    connect_timeout: 10,
    read_timeout: 10,
    write_timeout: 10
  )

  puts 'Connection created using factory method'
  puts 'Making request with connection from HttpClientUtils...'

  # Make the request
  response = connection.request(
    method: :get,
    path: '/get',
    query: {
      test: 'utils'
    }
  )

  puts "Response Status: #{response.status}"

  if response.status == 200
    data = JSON.parse(response.body)
    puts "Data received: #{data['args'].inspect}"
  else
    puts "Error: #{response.status} - #{response.body}"
  end
rescue StandardError => e
  puts "Request Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
end

puts "\nTest 4: Using convenience method for API Key"
puts '-----------------------------------------'

begin
  # Use the convenience method
  puts 'Creating connection with convenience method...'

  connection = Legate::Auth.create_api_key_connection(
    'https://httpbin.org',
    api_key: API_KEY,
    location: :query,
    name: 'apikey',
    token_store: token_store,
    connect_timeout: 10,
    read_timeout: 10,
    write_timeout: 10
  )

  puts 'Connection created with convenience method'
  puts 'Making request with middleware...'

  response = connection.request(
    method: :get,
    path: '/get',
    query: {
      test: 'convenience'
    }
  )

  puts "Response Status: #{response.status}"

  if response.status == 200
    data = JSON.parse(response.body)
    puts "Data received: #{data['args'].inspect}"
  else
    puts "Error: #{response.status} - #{response.body}"
  end
rescue StandardError => e
  puts "Request Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
end

puts "\nTest complete."
