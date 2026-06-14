#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of using the ServiceAccount authentication with automatic token exchange and refresh
#
# This example demonstrates how to authenticate using a service account JSON key file
# and make requests that are automatically authenticated.
#
# Usage:
#   ruby examples/advanced/auth/service_account.rb [path/to/service_account_key.json]

require 'bundler/setup'
require 'legate'
require 'json'
require 'fileutils'

# Check if a service account key file was provided
key_file_path = ARGV[0] || ENV['SERVICE_ACCOUNT_KEY_FILE']
unless key_file_path
  puts 'Error: Please provide a service account key JSON file as an argument'
  puts 'Usage: ruby examples/advanced/auth/service_account.rb [path/to/service_account_key.json]'
  puts 'Alternatively, set the SERVICE_ACCOUNT_KEY_FILE environment variable'
  exit 1
end

# Ensure the key file exists
unless File.exist?(key_file_path)
  puts "Error: Service account key file not found: #{key_file_path}"
  exit 1
end

# Load the service account key file
begin
  service_account_key = JSON.parse(File.read(key_file_path))
  puts "Loaded service account key for: #{service_account_key['client_email']}"
rescue JSON::ParserError => e
  puts "Error parsing service account key file: #{e.message}"
  exit 1
end

# Create the Auth::Credential for the service account
# You can use either the raw JSON key or the individual components
credential = if ENV['USE_RAW_JSON'] == 'true'
               Legate::Auth::Credential.new(
                 auth_type: :service_account,
                 service_account_key: File.read(key_file_path)
               )
             else
               Legate::Auth::Credential.new(
                 auth_type: :service_account,
                 client_email: service_account_key['client_email'],
                 private_key: service_account_key['private_key'],
                 token_uri: service_account_key['token_uri']
               )
             end

# Create a Google Service Account scheme with the appropriate scopes
# You can use other service account implementations as well
scheme = Legate::Auth::Schemes::GoogleServiceAccount.new(
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
  # Optional custom audience if needed:
  # audience: 'https://your-api.example.com'
)

# Create a session service to manage authentication state
session_service = Legate::SessionService::InMemory.new

# Create a token store (optional but recommended for caching tokens)
token_store = Legate::Auth::TokenStore.new(session_service: session_service)

# Create the service account coordinator
coordinator = Legate::Auth::Coordinators::ServiceAccountCoordinator.new(
  scheme: scheme,
  credential: credential,
  session_service: session_service,
  token_store: token_store
)

# Authenticate and get the token
begin
  token = Legate::Auth.authenticate_with_coordinator(coordinator)
  puts 'Successfully authenticated with service account'
  puts "Access token: #{token.access_token[0..10]}... (expires in #{token[:expires_in]} seconds)"
rescue Legate::Auth::Error => e
  puts "Authentication failed: #{e.message}"
  exit 1
end

# Example of making an authenticated request with the token
require 'faraday'

puts "\nMaking an authenticated request..."
conn = Faraday.new(url: 'https://www.googleapis.com/storage/v1') do |builder|
  builder.request :authorization, 'Bearer', token.access_token
  builder.request :json
  builder.response :json
  builder.adapter Faraday.default_adapter
end

# Example: List Google Cloud Storage buckets
begin
  response = conn.get('b', { project: service_account_key['project_id'] })

  if response.success?
    puts "Request succeeded with status: #{response.status}"
    puts "Found #{response.body['items']&.length || 0} buckets"

    if response.body['items']&.any?
      puts "\nBucket names:"
      response.body['items'].each do |bucket|
        puts "- #{bucket['name']}"
      end
    end
  else
    puts "Request failed with status: #{response.status}"
    puts "Error: #{response.body['error']&.dig('message') || response.body.inspect}"
  end
rescue StandardError => e
  puts "Request failed: #{e.message}"
end

puts "\nToken refresh demonstration:"
puts "Current token will expire in #{token[:expires_in]} seconds"
puts 'Explicitly refreshing token...'

# Example of refreshing a token
begin
  refreshed_token = coordinator.refresh(token)
  puts 'Token refreshed successfully'
  puts "New access token: #{refreshed_token.access_token[0..10]}... (expires in #{refreshed_token[:expires_in]} seconds)"
rescue Legate::Auth::Error => e
  puts "Token refresh failed: #{e.message}"
end

puts "\nDemonstration completed successfully!"
