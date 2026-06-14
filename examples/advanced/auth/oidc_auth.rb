#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of using OpenID Connect (OIDC) authentication with Legate
#
# This example demonstrates how to use OIDC authentication to make authenticated requests
# and retrieve user profile information from an identity provider.
#
# Usage:
#   ruby examples/advanced/auth/oidc_auth.rb [--with-server]
#   ruby examples/advanced/auth/oidc_auth.rb --client-id=YOUR_CLIENT_ID --client-secret=YOUR_CLIENT_SECRET --provider=google
#
# Set these environment variables to use your own OIDC provider:
#   OIDC_CLIENT_ID
#   OIDC_CLIENT_SECRET
#   OIDC_PROVIDER (default: google, supported: google, auth0)
#   OIDC_REDIRECT_URI (default: http://localhost:3000/auth/callback)

require 'bundler/setup'
require 'legate'
require 'legate/auth'
require 'legate/auth/runner'
require 'legate/auth/schemes/openid_connect'
require 'legate/tool_context'
require 'legate/web/server'
require 'launchy'
require 'securerandom'
require 'optparse'
require 'json'
require 'fileutils'

# Parse command line arguments
options = {
  with_server: false,
  client_id: ENV['OIDC_CLIENT_ID'],
  client_secret: ENV['OIDC_CLIENT_SECRET'],
  provider: ENV['OIDC_PROVIDER'] || 'google',
  redirect_uri: ENV['OIDC_REDIRECT_URI'] || 'http://localhost:3000/auth/callback',
  handle_response: false,
  request_id: nil,
  response_uri: nil,
  use_refresh_token: false,
  verbose: false
}

OptionParser.new do |opts|
  opts.banner = 'Usage: ruby examples/advanced/auth/oidc_auth.rb [options]'

  opts.on('--with-server', 'Start a local server to handle the OIDC callback') do
    options[:with_server] = true
  end

  opts.on('--client-id=ID', 'OIDC client ID') do |id|
    options[:client_id] = id
  end

  opts.on('--client-secret=SECRET', 'OIDC client secret') do |secret|
    options[:client_secret] = secret
  end

  opts.on('--provider=PROVIDER', 'OIDC provider (google, auth0)') do |provider|
    options[:provider] = provider
  end

  opts.on('--redirect-uri=URI', 'OIDC redirect URI') do |uri|
    options[:redirect_uri] = uri
  end

  opts.on('--handle-response', 'Handle an authentication response') do
    options[:handle_response] = true
  end

  opts.on('--request-id=ID', 'Authentication request ID') do |id|
    options[:request_id] = id
  end

  opts.on('--response-uri=URI', 'Authentication response URI') do |uri|
    options[:response_uri] = uri
  end

  opts.on('--use-refresh-token', 'Use a saved refresh token if available') do
    options[:use_refresh_token] = true
  end

  opts.on('--verbose', 'Enable verbose output') do
    options[:verbose] = true
  end

  opts.on('--help', 'Show this help message') do
    puts opts
    exit
  end
end.parse!

# Validate required parameters
if options[:client_id].nil? || options[:client_id].empty?
  puts 'Error: OIDC client ID is required'
  puts 'Please provide it via --client-id or OIDC_CLIENT_ID environment variable'
  exit 1
end

if options[:client_secret].nil? || options[:client_secret].empty?
  puts 'Error: OIDC client secret is required'
  puts 'Please provide it via --client-secret or OIDC_CLIENT_SECRET environment variable'
  exit 1
end

# Setup the session service
session_service = Legate::SessionService::InMemory.new

# Create a tool context with the session service
# In a real application, you would use Redis or another persistent storage
context = Legate::ToolContext.new(session_service: session_service)

# Create an OIDC scheme based on the selected provider
oidc_scheme = case options[:provider]&.downcase
              when 'google'
                Legate::Auth::Schemes::OpenIDConnect.new(
                  authorization_url: 'https://accounts.google.com/o/oauth2/auth',
                  token_url: 'https://oauth2.googleapis.com/token',
                  userinfo_url: 'https://openidconnect.googleapis.com/v1/userinfo',
                  jwks_uri: 'https://www.googleapis.com/oauth2/v3/certs',
                  scopes: %w[openid email profile],
                  fetch_userinfo: true,
                  use_pkce: true,
                  additional_params: {
                    prompt: 'consent',
                    access_type: 'offline'
                  }
                )
              when 'auth0'
                # Your Auth0 domain - replace with your actual domain
                domain = ENV['AUTH0_DOMAIN'] || 'your-domain.auth0.com'

                Legate::Auth::Schemes::OpenIDConnect.new(
                  authorization_url: "https://#{domain}/authorize",
                  token_url: "https://#{domain}/oauth/token",
                  userinfo_url: "https://#{domain}/userinfo",
                  jwks_uri: "https://#{domain}/.well-known/jwks.json",
                  scopes: %w[openid email profile],
                  fetch_userinfo: true,
                  use_pkce: true
                )
              else
                puts "Warning: Unsupported provider '#{options[:provider]}'. Using Google as default."

                Legate::Auth::Schemes::OpenIDConnect.new(
                  authorization_url: 'https://accounts.google.com/o/oauth2/auth',
                  token_url: 'https://oauth2.googleapis.com/token',
                  userinfo_url: 'https://openidconnect.googleapis.com/v1/userinfo',
                  jwks_uri: 'https://www.googleapis.com/oauth2/v3/certs',
                  scopes: %w[openid email profile],
                  fetch_userinfo: true,
                  use_pkce: true,
                  additional_params: {
                    prompt: 'consent',
                    access_type: 'offline'
                  }
                )
              end

# Create the OIDC credential
credential = Legate::Auth::Credential.new(
  auth_type: :oidc,
  client_id: options[:client_id],
  client_secret: options[:client_secret]
)

# Token storage file for refresh tokens
token_storage_file = File.expand_path('~/.oidc_example_token.json')

# Helper to save token to file
def save_token_to_file(token, file_path)
  # Convert token to a hash for storage
  token_data = {
    access_token: token.access_token,
    refresh_token: token.refresh_token,
    token_type: token.token_type,
    expires_at: token.expires_at.to_i,
    scope: token.scope,
    id_token: token[:id_token],
    metadata: token.metadata
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
    Legate::Auth::ExchangedCredential.new(
      auth_type: :oidc,
      access_token: token_data[:access_token],
      refresh_token: token_data[:refresh_token],
      token_type: token_data[:token_type],
      expires_at: Time.at(token_data[:expires_at]),
      scope: token_data[:scope],
      id_token: token_data[:id_token],
      metadata: token_data[:metadata]
    )
  rescue StandardError => e
    puts "Error loading token: #{e.message}"
    nil
  end
end

# Create a web server to handle the OIDC callback
def create_callback_server(context, request_id_holder)
  server = Legate::Web::Server.new(port: 3000)

  # Add a route to handle the OIDC callback
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
            <title>OIDC Authentication Successful</title>
            <style>
              body { font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; }
              h1 { color: #4CAF50; }
              .box { border: 1px solid #ddd; border-radius: 5px; padding: 20px; margin-top: 20px; }
            </style>
          </head>
          <body>
            <h1>Authentication Successful</h1>
            <p>You have successfully authenticated with the OpenID Connect provider.</p>
            <div class="box">
              <p>You can close this window and return to the application.</p>
            </div>
          </body>
          </html>
        HTML
      else
        res.status = 400
        res.body = 'No active authentication request found'
      end
    else
      res.status = 400
      res.body = 'Missing required parameters'
    end
  end

  server
end

# Helper to fetch user information
def fetch_user_info(token, oidc_scheme)
  return {} unless token&.access_token && oidc_scheme.userinfo_url

  begin
    require 'faraday'

    conn = Faraday.new do |builder|
      builder.adapter Faraday.default_adapter
    end

    response = conn.get(oidc_scheme.userinfo_url) do |req|
      req.headers['Authorization'] = "#{token.token_type} #{token.access_token}"
      req.headers['Accept'] = 'application/json'
    end

    if response.status == 200
      JSON.parse(response.body, symbolize_names: true)
    else
      { error: "Failed to fetch user info: #{response.status}" }
    end
  rescue StandardError => e
    { error: "Error fetching user info: #{e.message}" }
  end
end

def display_user_info(user_info)
  return puts 'No user info available' if user_info.nil? || user_info.empty?

  puts "\nUser Information:"
  puts "  Name        : #{user_info[:name] || 'N/A'}"
  puts "  Email       : #{user_info[:email] || 'N/A'}"
  puts "  Picture     : #{user_info[:picture] ? 'Available' : 'N/A'}"
  puts "  Locale      : #{user_info[:locale] || 'N/A'}"

  puts "  Subject ID  : #{user_info[:sub]}" if user_info[:sub]

  # Display additional fields if available
  additional_fields = user_info.keys - %i[name email picture locale sub error]
  return unless additional_fields.any?

  puts '  Additional Information:'
  additional_fields.each do |field|
    puts "    #{field}: #{user_info[field]}"
  end
end

def make_authenticated_request(token, oidc_scheme)
  # In a real application, you would make an API call to an OIDC-protected endpoint
  # This is just a simulation to show the token information
  puts "\nMaking an authenticated request with token:"
  puts "  Access Token : #{token.access_token[0..9]}...#{token.access_token[-4..-1]}"
  puts "  Token Type   : #{token.token_type}"
  puts "  Expires In   : #{(token.expires_at - Time.now).to_i} seconds"
  puts "  Scopes       : #{token.scope}"

  # Print ID token if available
  puts "  ID Token    : #{token[:id_token][0..9]}...#{token[:id_token][-4..-1]}" if token[:id_token]

  # Print refresh token if available
  puts "  Refresh Token: #{token.refresh_token[0..5]}...#{token.refresh_token[-4..-1]}" if token.refresh_token

  # Get user info from token metadata or fetch it
  user_info = token.metadata&.dig(:userinfo)

  if !user_info && token.access_token
    puts "\nFetching user information..."
    user_info = fetch_user_info(token, oidc_scheme)

    # Store user info in token metadata for future use
    if user_info && !user_info[:error]
      token.metadata ||= {}
      token.metadata[:userinfo] = user_info
    end
  end

  # Display user information
  display_user_info(user_info)

  puts "\nAuthenticated request successful!"

  {
    status: 'success',
    authenticated: true,
    auth_method: 'OIDC',
    token_expiry: token.expires_at,
    scopes: token.scope,
    user_info: user_info
  }
end

# Main execution logic
begin
  # Try to use saved refresh token
  saved_token = nil
  if options[:use_refresh_token] && File.exist?(token_storage_file)
    puts 'Found saved token, attempting to use it...'
    saved_token = load_token_from_file(token_storage_file)

    if saved_token
      if saved_token.expired?
        puts 'Saved token is expired, attempting to refresh it...'

        # Create a token store
        token_store = Legate::Auth::TokenStore.new(session_service: session_service)

        # Create a token manager
        token_manager = Legate::Auth::TokenManager.new(token_store)

        # Refresh the token
        begin
          refreshed_token = token_manager.refresh_token(oidc_scheme, credential, saved_token)
          puts 'Token refreshed successfully!'

          # Save the refreshed token
          save_token_to_file(refreshed_token, token_storage_file)

          # Make a request with the refreshed token
          result = make_authenticated_request(refreshed_token, oidc_scheme)
          puts "\nAuthentication via refresh token successful!"
          exit 0
        rescue StandardError => e
          puts "Token refresh failed: #{e.message}"
          puts 'Will proceed with interactive authentication...'
          # Continue with interactive flow below
        end
      else
        puts 'Saved token is still valid, using it...'
        result = make_authenticated_request(saved_token, oidc_scheme)
        puts "\nAuthentication with saved token successful!"
        exit 0
      end
    end
  end

  # Handle authentication response if requested
  if options[:handle_response]
    unless options[:request_id] && options[:response_uri]
      puts 'Error: Both --request-id and --response-uri are required with --handle-response'
      exit 1
    end

    puts "Handling authentication response for request ID: #{options[:request_id]}"

    # Create a response object
    response = { 'response_uri' => options[:response_uri] }

    # Handle the authentication response
    result = context.handle_auth_response(options[:request_id], response)

    if result[:status] == :completed
      puts 'Authentication completed successfully!'
      token = result[:credential]

      # Save the token for future use
      save_token_to_file(token, token_storage_file)

      # Make a request with the token
      make_authenticated_request(token, oidc_scheme)
    else
      puts 'Authentication not completed:'
      puts result.inspect
    end

    exit 0
  end

  # Start server if requested
  if options[:with_server]
    puts 'Starting local server to handle OIDC callback...'
    request_id_holder = { id: nil }
    server = create_callback_server(context, request_id_holder)

    begin
      # Start the server
      server_thread = Thread.new { server.start }

      # Use with_authentication to create a fiber context with auth support
      result = context.with_authentication do
        # This callback will be called when an authentication request is yielded

        # Authenticate with the scheme and credential
        token = context.auth_session(
          oidc_scheme,
          credential,
          redirect_uri: options[:redirect_uri]
        )

        if token
          # Save the token for future use
          save_token_to_file(token, token_storage_file)

          # Make authenticated request
          make_authenticated_request(token, oidc_scheme)
        else
          puts 'Failed to get authentication token'
          { status: :error, message: 'Authentication failed' }
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
    puts 'Starting OIDC authentication process...'

    # Create an auth runner
    auth_runner = Legate::Auth::Runner.new(session_service: session_service)

    # Start authentication
    auth_result = auth_runner.authenticate(oidc_scheme, credential,
                                           redirect_uri: options[:redirect_uri])

    # Check if we got a token immediately (unlikely for OIDC)
    if auth_result.is_a?(Legate::Auth::ExchangedCredential)
      puts 'Received token immediately (unusual for OIDC):'
      make_authenticated_request(auth_result, oidc_scheme)
    else
      # We should have an authentication request
      request_id = auth_result[:request_id]
      auth_request = auth_result[:auth_request]

      puts 'Authentication required. Please visit this URL to authorize:'
      puts "  #{auth_request[:url]}"
      puts
      puts 'After authorization, you will be redirected. Copy the entire URL from your browser'
      puts 'and run this command to complete authentication:'
      puts
      puts "  ruby #{__FILE__} --handle-response --request-id #{request_id} --response-uri 'PASTE_URL_HERE'"
    end
  end
rescue StandardError => e
  puts "Error: #{e.class}: #{e.message}"
  puts e.backtrace.join("\n") if options[:verbose]
end
