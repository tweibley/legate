#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of using OAuth2 authentication with ADK
#
# This example demonstrates how to use OAuth2 authentication to make authenticated requests
# to an API that requires OAuth2 authorization. It shows both the interactive and non-interactive
# (with refresh token) approaches.
#
# Usage:
#   ruby examples/auth/oauth2_auth.rb [--with-server]
#   ruby examples/auth/oauth2_auth.rb --client-id=YOUR_CLIENT_ID --client-secret=YOUR_CLIENT_SECRET
#
# Set these environment variables to use your own OAuth2 provider:
#   OAUTH_CLIENT_ID
#   OAUTH_CLIENT_SECRET
#   OAUTH_AUTH_URL (default: https://accounts.google.com/o/oauth2/auth)
#   OAUTH_TOKEN_URL (default: https://oauth2.googleapis.com/token)
#   OAUTH_REDIRECT_URI (default: http://localhost:3000/auth/callback)

require 'bundler/setup'
require 'adk'
require 'adk/auth'
require 'adk/auth/runner'
require 'adk/auth/schemes/oauth2'
require 'adk/tool_context'
require 'adk/web/server'
require 'launchy'
require 'securerandom'
require 'optparse'
require 'json'
require 'fileutils'

# Parse command line arguments
options = {
  with_server: false,
  client_id: ENV['OAUTH_CLIENT_ID'],
  client_secret: ENV['OAUTH_CLIENT_SECRET'],
  auth_url: ENV['OAUTH_AUTH_URL'] || 'https://accounts.google.com/o/oauth2/auth',
  token_url: ENV['OAUTH_TOKEN_URL'] || 'https://oauth2.googleapis.com/token',
  redirect_uri: ENV['OAUTH_REDIRECT_URI'] || 'http://localhost:3000/auth/callback',
  scopes: ENV['OAUTH_SCOPES'] || 'email profile',
  handle_response: false,
  request_id: nil,
  response_uri: nil,
  use_refresh_token: false,
  verbose: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby examples/auth/oauth2_auth.rb [options]"

  opts.on("--with-server", "Start a local server to handle the OAuth2 callback") do
    options[:with_server] = true
  end
  
  opts.on("--client-id=ID", "OAuth2 client ID") do |id|
    options[:client_id] = id
  end
  
  opts.on("--client-secret=SECRET", "OAuth2 client secret") do |secret|
    options[:client_secret] = secret
  end
  
  opts.on("--auth-url=URL", "OAuth2 authorization URL") do |url|
    options[:auth_url] = url
  end
  
  opts.on("--token-url=URL", "OAuth2 token URL") do |url|
    options[:token_url] = url
  end
  
  opts.on("--redirect-uri=URI", "OAuth2 redirect URI") do |uri|
    options[:redirect_uri] = uri
  end
  
  opts.on("--scopes=SCOPES", "OAuth2 scopes (space-separated)") do |scopes|
    options[:scopes] = scopes
  end
  
  opts.on("--handle-response", "Handle an authentication response") do
    options[:handle_response] = true
  end
  
  opts.on("--request-id=ID", "Authentication request ID") do |id|
    options[:request_id] = id
  end
  
  opts.on("--response-uri=URI", "Authentication response URI") do |uri|
    options[:response_uri] = uri
  end
  
  opts.on("--use-refresh-token", "Use a saved refresh token if available") do
    options[:use_refresh_token] = true
  end
  
  opts.on("--verbose", "Enable verbose output") do
    options[:verbose] = true
  end
  
  opts.on("--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Validate required parameters
if options[:client_id].nil? || options[:client_id].empty?
  puts "Error: OAuth2 client ID is required"
  puts "Please provide it via --client-id or OAUTH_CLIENT_ID environment variable"
  exit 1
end

if options[:client_secret].nil? || options[:client_secret].empty?
  puts "Error: OAuth2 client secret is required"
  puts "Please provide it via --client-secret or OAUTH_CLIENT_SECRET environment variable"
  exit 1
end

# Setup the session service
session_service = ADK::SessionService::InMemory.new

# Create a tool context with the session service
# In a real application, you would use Redis or another persistent storage
context = ADK::ToolContext.new(session_service: session_service)

# Create an OAuth2 scheme
oauth2_scheme = ADK::Auth::Schemes::OAuth2.new(
  authorization_url: options[:auth_url],
  token_url: options[:token_url],
  scopes: options[:scopes].split(' '),
  use_pkce: true,
  additional_params: {
    prompt: 'consent',
    access_type: 'offline'
  }
)

# Create the OAuth2 credential
credential = ADK::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: options[:client_id],
  client_secret: options[:client_secret]
)

# Token storage file for refresh tokens
token_storage_file = File.expand_path("~/.oauth2_example_token.json")

# Helper to save token to file
def save_token_to_file(token, file_path)
  # Convert token to a hash for storage
  token_data = {
    access_token: token.access_token,
    refresh_token: token.refresh_token,
    token_type: token.token_type,
    expires_at: token.expires_at.to_i,
    scope: token.scope
  }.compact
  
  # Save to file
  FileUtils.mkdir_p(File.dirname(file_path))
  File.write(file_path, JSON.pretty_generate(token_data))
  puts "Token saved to #{file_path}"
end

# Helper to load token from file
def load_token_from_file(file_path)
  return nil unless File.exist?(file_path)
  
  begin
    token_data = JSON.parse(File.read(file_path), symbolize_names: true)
    
    # Create an exchanged credential from the stored data
    ADK::Auth::ExchangedCredential.new(
      auth_type: :oauth2,
      access_token: token_data[:access_token],
      refresh_token: token_data[:refresh_token],
      token_type: token_data[:token_type],
      expires_at: Time.at(token_data[:expires_at]),
      scope: token_data[:scope]
    )
  rescue => e
    puts "Error loading token: #{e.message}"
    nil
  end
end

# Create a web server to handle the OAuth2 callback
def create_callback_server(context, request_id_holder)
  server = ADK::Web::Server.new(port: 3000)
  
  # Add a route to handle the OAuth2 callback
  server.add_route('GET', '/auth/callback') do |req, res|
    # Extract the authorization code from the query parameters
    code = req.query['code']
    state = req.query['state']
    error = req.query['error']
    
    if error
      res.status = 400
      res.body = "Authentication failed: #{error}"
    elsif code
      # Convert the request to a response URI
      response_uri = "http://localhost:3000/auth/callback?#{req.query_string}"
      
      # Find the active auth request
      request_id = request_id_holder[:id] || nil
      
      if request_id
        # Handle the auth response
        result = context.handle_auth_response(request_id, { 'response_uri' => response_uri })
        
        # Show a success page
        res.status = 200
        res.body = <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>Authentication Successful</title>
            <style>
              body { font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; }
              h1 { color: #4CAF50; }
              .box { border: 1px solid #ddd; border-radius: 5px; padding: 20px; margin-top: 20px; }
            </style>
          </head>
          <body>
            <h1>Authentication Successful</h1>
            <p>You have successfully authenticated with the OAuth2 provider.</p>
            <div class="box">
              <p>You can close this window and return to the application.</p>
            </div>
          </body>
          </html>
        HTML
      else
        res.status = 400
        res.body = "No active authentication request found"
      end
    else
      res.status = 400
      res.body = "Missing required parameters"
    end
  end
  
  server
end

def make_authenticated_request(token)
  # In a real application, you would make an API call to an OAuth2-protected endpoint
  # This is just a simulation to show the token information
  puts "\nMaking an authenticated request with token:"
  puts "  Access Token : #{token.access_token[0..9]}...#{token.access_token[-4..-1]}"
  puts "  Token Type   : #{token.token_type}"
  puts "  Expires In   : #{(token.expires_at - Time.now).to_i} seconds"
  puts "  Scopes       : #{token.scope}"
  
  # Print refresh token if available
  if token.refresh_token
    puts "  Refresh Token: #{token.refresh_token[0..5]}...#{token.refresh_token[-4..-1]}"
  end
  
  puts "\nAuthenticated request successful!"
  
  {
    status: "success",
    authenticated: true,
    auth_method: "OAuth2",
    token_expiry: token.expires_at,
    scopes: token.scope
  }
end

# Main execution logic
begin
  # Try to use saved refresh token
  saved_token = nil
  if options[:use_refresh_token] && File.exist?(token_storage_file)
    puts "Found saved token, attempting to use it..."
    saved_token = load_token_from_file(token_storage_file)
    
    if saved_token
      if saved_token.expired?
        puts "Saved token is expired, attempting to refresh it..."
        
        # Create a token store
        token_store = ADK::Auth::TokenStore.new(session_service: session_service)
        
        # Create a token manager
        token_manager = ADK::Auth::TokenManager.new(token_store)
        
        # Refresh the token
        begin
          refreshed_token = token_manager.refresh_token(oauth2_scheme, credential, saved_token)
          puts "Token refreshed successfully!"
          
          # Save the refreshed token
          save_token_to_file(refreshed_token, token_storage_file)
          
          # Make a request with the refreshed token
          result = make_authenticated_request(refreshed_token)
          puts "\nAuthentication via refresh token successful!"
          exit 0
        rescue => e
          puts "Token refresh failed: #{e.message}"
          puts "Will proceed with interactive authentication..."
          # Continue with interactive flow below
        end
      else
        puts "Saved token is still valid, using it..."
        result = make_authenticated_request(saved_token)
        puts "\nAuthentication with saved token successful!"
        exit 0
      end
    end
  end
  
  # Handle authentication response if requested
  if options[:handle_response]
    unless options[:request_id] && options[:response_uri]
      puts "Error: Both --request-id and --response-uri are required with --handle-response"
      exit 1
    end
    
    puts "Handling authentication response for request ID: #{options[:request_id]}"
    
    # Create a response object
    response = { 'response_uri' => options[:response_uri] }
    
    # Handle the authentication response
    result = context.handle_auth_response(options[:request_id], response)
    
    if result[:status] == :completed
      puts "Authentication completed successfully!"
      token = result[:credential]
      
      # Save the token for future use
      save_token_to_file(token, token_storage_file)
      
      # Make a request with the token
      make_authenticated_request(token)
    else
      puts "Authentication not completed:"
      puts result.inspect
    end
    
    exit 0
  end
  
  # Start server if requested
  if options[:with_server]
    puts "Starting local server to handle OAuth2 callback..."
    request_id_holder = { id: nil }
    server = create_callback_server(context, request_id_holder)
    
    begin
      # Start the server
      server_thread = Thread.new { server.start }
      
      # Use with_authentication to create a fiber context with auth support
      result = context.with_authentication do
        # This callback will be called when an authentication request is yielded
        lambda do |auth_request|
          # Store the request ID for the callback server
          request_id = auth_request[:request_id]
          request_id_holder[:id] = request_id
          
          # Extract the authorization URL from the auth request
          if auth_request[:auth_request][:type] == 'authorization_request'
            auth_url = auth_request[:auth_request][:url]
            
            # Open the browser with the authorization URL
            puts "Opening browser to authorize at: #{auth_url}"
            Launchy.open(auth_url)
            
            puts "Waiting for OAuth2 callback..."
          else
            puts "Unhandled auth request type: #{auth_request[:auth_request][:type]}"
          end
          
          # Return nil to continue waiting for the callback
          nil
        end
        
        # Authenticate with the scheme and credential
        token = context.auth_session(
          oauth2_scheme,
          credential,
          redirect_uri: options[:redirect_uri]
        )
        
        if token
          # Save the token for future use
          save_token_to_file(token, token_storage_file)
          
          # Make authenticated request
          make_authenticated_request(token)
        else
          puts "Failed to get authentication token"
          { status: :error, message: "Authentication failed" }
        end
      end
      
      puts "Result: #{result.inspect}"
    ensure
      # Stop the server
      server.stop
      # Wait for server thread to finish
      server_thread.join if server_thread
    end
  else
    # Manual flow without a local server
    puts "Starting OAuth2 authentication process..."
    
    # Create an auth runner
    auth_runner = ADK::Auth::Runner.new(session_service: session_service)
    
    # Start authentication
    auth_result = auth_runner.authenticate(oauth2_scheme, credential, 
                                          redirect_uri: options[:redirect_uri])
    
    # Check if we got a token immediately (unlikely for OAuth2)
    if auth_result.is_a?(ADK::Auth::ExchangedCredential)
      puts "Received token immediately (unusual for OAuth2):"
      make_authenticated_request(auth_result)
    else
      # We should have an authentication request
      request_id = auth_result[:request_id]
      auth_request = auth_result[:auth_request]
      
      puts "Authentication required. Please visit this URL to authorize:"
      puts "  #{auth_request[:url]}"
      puts
      puts "After authorization, you will be redirected. Copy the entire URL from your browser"
      puts "and run this command to complete authentication:"
      puts
      puts "  ruby #{__FILE__} --handle-response --request-id #{request_id} --response-uri 'PASTE_URL_HERE'"
    end
  end
rescue => e
  puts "Error: #{e.class}: #{e.message}"
  puts e.backtrace.join("\n") if options[:verbose]
end 