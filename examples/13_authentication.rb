#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of using HTTP Bearer authentication with Legate
#
# This example demonstrates how to use HTTP Bearer authentication to make authenticated requests
# to an API that requires a bearer token in the Authorization header.
#
# Usage:
#   ruby examples/13_authentication.rb [token]

require 'bundler/setup'
require 'legate'

# Load .env and map GEMINI_API_KEY -> GOOGLE_API_KEY (as the `legate` CLI does).
# The library never reads .env on its own; an application must opt in.
Legate.load_environment
require 'legate/auth'
require 'legate/auth/schemes/http_bearer'
require 'json'

# Check if a bearer token was provided
bearer_token = ARGV[0] || ENV['BEARER_TOKEN']
unless bearer_token
  puts 'Error: Please provide a bearer token as an argument'
  puts 'Usage: ruby examples/13_authentication.rb [token]'
  puts 'Alternatively, set the BEARER_TOKEN environment variable'
  exit 1
end

puts "Using Bearer Token: #{bearer_token[0..5]}..." + ('*' * 10)

# Create the Auth::Credential with the bearer token
credential = Legate::Auth::Credential.new(
  auth_type: :http_bearer,
  bearer_token: bearer_token
)

# Create a session service to manage authentication state
session_service = Legate::SessionService::InMemory.new

# Create a token store (optional but recommended for consistency)
token_store = Legate::Auth::TokenStore.new(session_service: session_service)

puts "\n=== Example 1: Basic HTTP Bearer Authentication ==="
# Create an HTTP Bearer scheme
bearer_scheme = Legate::Auth::Schemes::HTTPBearer.new

# For simple non-interactive schemes like HTTP Bearer, we can use the token directly
exchanged_token = bearer_scheme.exchange_token(credential)
puts 'Generated token for HTTP Bearer authentication'

# Example of making a request with the bearer token
require 'excon'
conn = Excon.new('https://httpbin.org')

# Prepare request with authentication
request = {
  path: '/headers',
  headers: {
    'Accept' => 'application/json'
  }
}

# Apply authentication
request = bearer_scheme.apply_to_request(request, exchanged_token)

begin
  response = conn.get(request)

  if response.status == 200
    puts "Request succeeded with status: #{response.status}"
    puts 'Headers received by server:'
    JSON.parse(response.body)['headers'].each do |name, value|
      puts "  #{name}: #{value}"
    end
  else
    puts "Request failed with status: #{response.status}"
    puts "Error: #{response.body}"
  end
rescue StandardError => e
  puts "Request failed: #{e.message}"
end

puts "\n=== Example 2: HTTP Bearer with Expiry Simulation ==="
# In real-world scenarios, bearer tokens often expire
# This example simulates a token with expiry information

# Create a token with expiry information
expiring_token = Legate::Auth::ExchangedCredential.new(
  auth_type: :http_bearer,
  access_token: bearer_token,
  bearer_token: bearer_token,
  expires_in: 3600, # Token expires in 1 hour
  token_type: 'Bearer'
)

puts "Token expires in: #{expiring_token[:expires_in]} seconds"

# Example of checking token expiry
if expiring_token.expired?
  puts 'Token has expired and needs to be refreshed'
else
  remaining = expiring_token.expires_at - Time.now
  puts "Token is still valid for #{remaining.to_i} seconds"
end

puts "\n=== Example 3: Using with the Legate Excon Middleware ==="

# Create the Excon middleware for HTTP Bearer authentication
middleware = Legate::Auth.create_middleware(
  scheme: bearer_scheme,
  credential: credential
)

# Create an Excon connection with the middleware
connection = Legate::Auth.create_connection(
  'https://httpbin.org',
  scheme: bearer_scheme,
  credential: credential
)

begin
  response = connection.get(
    path: '/headers',
    headers: { 'Accept' => 'application/json' }
  )

  if response.status == 200
    puts "Excon request succeeded with status: #{response.status}"
    headers = JSON.parse(response.body)['headers']
    puts 'Headers received by server:'
    headers.each do |name, value|
      puts "  #{name}: #{value}"
    end
  else
    puts "Excon request failed with status: #{response.status}"
    puts "Error: #{response.body}"
  end
rescue StandardError => e
  puts "Excon request failed: #{e.message}"
end

puts "\n=== Example 4: Using with the Legate Tooling System ==="
# Example of a tool using bearer authentication
class BearerAuthExampleTool < Legate::Tool
  include Legate::Tools::Base::HttpClient

  tool_description 'Example tool demonstrating HTTP Bearer authentication'

  parameter :endpoint,
            type: :string,
            description: 'API endpoint to call',
            required: true

  def initialize(options = {})
    super()
    @auth_scheme = options[:auth_scheme]
    @auth_credential = options[:auth_credential]
    setup_http_client(
      base_url: 'https://httpbin.org',
      options: {
        connect_timeout: 3,
        read_timeout: 3,
        write_timeout: 3
      }
    )
  end

  private

  def perform_execution(params, _context)
    # Prepare request with authentication
    request = {
      method: :get,
      path: "/#{params[:endpoint]}",
      headers: {
        'Accept' => 'application/json'
      }
    }

    # Apply authentication if configured
    request = @auth_scheme.apply_to_request(request, @auth_credential) if @auth_scheme && @auth_credential

    # Make the request
    response = http_get(
      request[:path],
      headers: request[:headers]
    )

    # Parse and return the response
    data = JSON.parse(response.body)
    {
      status: :success,
      endpoint: params[:endpoint],
      headers: data['headers'],
      data: data
    }
  end
end

# Create and use the example tool
example_tool = BearerAuthExampleTool.new(
  auth_scheme: bearer_scheme,
  auth_credential: credential
)

puts "\nTesting bearer auth tool with endpoint: headers"
begin
  result = example_tool.execute(endpoint: 'headers')
  puts 'Tool execution succeeded!'
  puts 'Response headers:'
  result[:headers].each do |name, value|
    puts "  #{name}: #{value}"
  end
rescue StandardError => e
  puts "Tool execution failed: #{e.message}"
end

puts "\nHTTP Bearer authentication example completed successfully!"
