# frozen_string_literal: true

require 'bundler/setup'
require 'legate'
require 'legate/auth'
require 'legate/auth/runner'
require 'legate/auth/schemes/openid_connect'
require 'legate/tool_context'
require 'legate/web/server'
require 'launchy'
require 'securerandom'
require 'json'

# This example demonstrates the fiber-based OIDC (OpenID Connect) authentication flow
# It shows how to:
# 1. Set up an authentication runner with OIDC
# 2. Use the auth_session method within a tool
# 3. Handle authentication requests and responses
# 4. Retrieve user information from the identity provider
# 5. Launch a browser for OIDC authorization
# 6. Start a temporary web server to receive the OIDC callback

class OIDCExampleTool < Legate::Tool::Base
  name :oidc_example_tool
  description 'Example tool demonstrating fiber-based OIDC authentication'
  version '1.0.0'

  parameter :action, type: :symbol, required: true,
                     description: 'Action to perform (call_api, handle_response, run_with_server)'
  parameter :request_id, type: :string, required: false,
                         description: 'The authentication request ID for handling responses'
  parameter :response_uri, type: :string, required: false,
                           description: 'The response URI from the OIDC callback'
  parameter :client_id, type: :string, required: false,
                        description: 'OIDC client ID'
  parameter :client_secret, type: :string, required: false,
                            description: 'OIDC client secret'
  parameter :provider, type: :string, required: false, default: 'google',
                       description: 'OIDC provider (google, auth0, etc.)'

  def execute
    case parameters[:action]
    when :call_api
      # Use with_authentication to create a fiber context with auth support
      context.with_authentication do
        call_api_with_auth
      end
    when :handle_response
      # Handle an authentication response
      handle_auth_response
    when :run_with_server
      # Run with a local server to automatically handle the OIDC callback
      run_with_local_server
    else
      raise Legate::ToolError, "Unknown action: #{parameters[:action]}"
    end
  end

  private

  def call_api_with_auth
    # Define an OIDC scheme
    oidc_scheme = create_oidc_scheme

    # Define a credential
    credential = create_credential

    # Start an authentication session
    # This will yield the fiber if authentication is needed
    token = context.auth_session(
      oidc_scheme,
      credential,
      redirect_uri: 'http://localhost:3000/auth/callback'
    )

    # If we get here, we have a valid token
    if token
      # Get user info from the token metadata or fetch it if needed
      user_info = token.metadata&.dig(:userinfo) || fetch_user_info(token, oidc_scheme)

      # Simulate an API call with the token
      api_call_result = simulate_api_call(token)

      {
        status: :success,
        message: 'Successfully authenticated and called API',
        token_type: token.token_type,
        expires_in: token.expires_in,
        scope: token.scope,
        user_info: user_info,
        api_result: api_call_result
      }
    else
      { status: :error, message: 'Failed to authenticate' }
    end
  end

  def handle_auth_response
    # Get required parameters
    request_id = parameters[:request_id]
    response_uri = parameters[:response_uri]

    raise Legate::ToolArgumentError, 'Both request_id and response_uri are required' unless request_id && response_uri

    # Create a response object
    response = { 'response_uri' => response_uri }

    # Handle the authentication response
    result = context.handle_auth_response(request_id, response)

    # Return the result
    {
      status: result[:status],
      message: result[:status] == :completed ? 'Authentication completed' : 'Authentication in progress',
      details: result
    }
  end

  def run_with_local_server
    # Create a web server to handle the OIDC callback
    server = create_callback_server

    begin
      # Start the server
      server_thread = Thread.new { server.start }

      # Use with_authentication to create a fiber context with auth support
      result = context.with_authentication do
        # This callback will be called when an authentication request is yielded

        # Call API with authentication
        call_api_with_auth
      end

      result
    ensure
      # Stop the server
      server.stop
      # Wait for server thread to finish
      server_thread.join if server_thread
    end
  end

  def create_oidc_scheme
    # Configure based on the selected provider
    case parameters[:provider]&.downcase
    when 'google'
      Legate::Auth::Schemes::OpenIDConnect.new(
        authorization_url: 'https://accounts.google.com/o/oauth2/auth',
        token_url: 'https://oauth2.googleapis.com/token',
        userinfo_url: 'https://openidconnect.googleapis.com/v1/userinfo',
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
        scopes: %w[openid email profile],
        fetch_userinfo: true,
        use_pkce: true
      )
    else
      # Default to a generic configuration
      Legate::Auth::Schemes::OpenIDConnect.new(
        authorization_url: 'https://example.com/authorize',
        token_url: 'https://example.com/token',
        userinfo_url: 'https://example.com/userinfo',
        scopes: %w[openid email profile],
        fetch_userinfo: true,
        use_pkce: true
      )
    end
  end

  def create_credential
    client_id = parameters[:client_id] || ENV['OIDC_CLIENT_ID'] || 'your-client-id'
    client_secret = parameters[:client_secret] || ENV['OIDC_CLIENT_SECRET'] || 'your-client-secret'

    Legate::Auth::Credential.new(
      auth_type: :oidc,
      client_id: client_id,
      client_secret: client_secret
    )
  end

  def fetch_user_info(token, oidc_scheme)
    return {} unless token&.access_token && oidc_scheme.userinfo_url

    begin
      oidc_scheme.fetch_userinfo(token)
    rescue Legate::Auth::Error => e
      Legate.logger.warn("Failed to fetch userinfo: #{e.message}")
      { error: e.message }
    end
  end

  def simulate_api_call(token)
    # In a real application, you would make an actual API call using the token
    # This is just a simulation
    {
      api_name: 'Example OIDC API',
      called_at: Time.now.iso8601,
      authorization: "#{token.token_type} #{token.access_token[0..5]}...[truncated]"
    }
  end

  def create_callback_server
    # Create a simple web server to handle OIDC callbacks
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
        active_requests = context.instance_variable_get(:@auth_runner)&.instance_variable_get(:@active_coordinators)
        request_id = active_requests&.keys&.first

        if request_id
          # Handle the auth response
          result = context.handle_auth_response(request_id, { 'response_uri' => response_uri })

          # Show a success page with user info if available
          res.status = 200

          # Try to extract user info if available
          user_info = result[:credential]&.metadata&.dig(:userinfo)
          user_info_html = ''

          if user_info
            user_info_html = "<div style='margin-top: 20px; padding: 10px; background-color: #f5f5f5; border-radius: 5px;'>"
            user_info_html += '<h2>User Information</h2>'
            user_info_html += '<ul>'

            # Display some common OIDC user info fields
            user_info_html += "<li><strong>Name:</strong> #{user_info['name']}</li>" if user_info['name']
            user_info_html += "<li><strong>Email:</strong> #{user_info['email']}</li>" if user_info['email']
            user_info_html += "<li><strong>Picture:</strong> <img src='#{user_info['picture']}' width='50' height='50' style='border-radius: 50%;'/></li>" if user_info['picture']

            user_info_html += '</ul></div>'
          end

          res.body = <<~HTML
            <!DOCTYPE html>
            <html>
            <head>
              <title>Authentication Successful</title>
              <style>
                body { font-family: Arial, sans-serif; margin: 40px; text-align: center; }
                h1 { color: #2c3e50; }
                .container { max-width: 600px; margin: 0 auto; }
                .success { color: #27ae60; }
              </style>
            </head>
            <body>
              <div class="container">
                <h1>Authentication Successful</h1>
                <p class="success">✓ You have successfully authenticated</p>
                <p>You can close this window and return to the application.</p>
                #{user_info_html}
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

  def handle_auth_request_with_browser(auth_request)
    # Extract the authorization URL from the auth request
    if auth_request[:auth_request][:type] == 'authorization_request'
      auth_url = auth_request[:auth_request][:url]

      # Open the browser with the authorization URL
      puts "Opening browser to authorize: #{auth_url}"
      Launchy.open(auth_url)

      puts 'Waiting for OIDC callback...'
    else
      puts "Unhandled auth request type: #{auth_request[:auth_request][:type]}"
    end

    # Return nil to continue waiting for the callback
    nil
  end
end

# Register the tool
Legate.register_tool(OIDCExampleTool)

# Example usage:
# 1. Run with a local server to automatically handle the OIDC callback:
#    ruby fiber_oidc_example.rb --with-server --provider google
#
# 2. Set credentials via environment variables:
#    OIDC_CLIENT_ID='your-client-id' OIDC_CLIENT_SECRET='your-client-secret' ruby fiber_oidc_example.rb --with-server
if $PROGRAM_NAME == __FILE__
  # Setup a session service for the example
  require 'legate/session_service/in_memory'
  session_service = Legate::SessionService::InMemory.new

  # Create a tool context with the session service
  context = Legate::ToolContext.new(session_service: session_service)

  # Process command line arguments
  provider = 'google' # Default provider

  ARGV.each_with_index do |arg, index|
    provider = ARGV[index + 1] if arg == '--provider' && ARGV[index + 1]
  end

  # Create and run the tool
  tool = OIDCExampleTool.new

  begin
    # Run with a local server to automatically handle the OIDC callback
    if ARGV.include?('--with-server')
      puts "Starting OIDC authentication flow with provider: #{provider}"
      result = tool.run(context, action: :run_with_server, provider: provider)
      puts "\nResult:"
      begin
        puts JSON.pretty_generate(result)
      rescue StandardError
        puts result.inspect
      end
    elsif ARGV.include?('--handle-response')
      # Extract request_id and response_uri from args
      request_id = nil
      response_uri = nil

      ARGV.each_with_index do |arg, index|
        if arg == '--request-id' && ARGV[index + 1]
          request_id = ARGV[index + 1]
        elsif arg == '--response-uri' && ARGV[index + 1]
          response_uri = ARGV[index + 1]
        end
      end

      if request_id && response_uri
        result = tool.run(context, action: :handle_response, request_id: request_id, response_uri: response_uri)
        puts "Result: #{result.inspect}"
      else
        puts 'Error: --request-id and --response-uri parameters are required for --handle-response'
      end
    else
      # Attempt to call API - this will yield for authentication
      result = tool.run(context, action: :call_api, provider: provider)

      # The result will include auth_request if authentication is needed
      if result.is_a?(Hash) && result[:auth_request]
        puts 'Authentication required. Please visit:'
        puts result[:auth_request][:url] if result[:auth_request][:url]
        puts "\nAfter completing authentication, run:"
        puts "ruby #{__FILE__} --handle-response --request-id #{result[:request_id]} --response-uri 'PASTE_RESPONSE_URI_HERE'"
      else
        puts 'Result:'
        begin
          puts JSON.pretty_generate(result)
        rescue StandardError
          puts result.inspect
        end
      end
    end
  rescue StandardError => e
    puts "Error: #{e.class}: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']

    if e.message.include?('Authentication session not available')
      puts "\nNote: This example requires proper OIDC credentials."
      puts 'You can provide them as environment variables:'
      puts "OIDC_CLIENT_ID='your-client-id' OIDC_CLIENT_SECRET='your-client-secret' ruby #{__FILE__} --with-server --provider google"
    end
  end
end
