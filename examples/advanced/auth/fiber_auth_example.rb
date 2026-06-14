# frozen_string_literal: true

require 'bundler/setup'
require 'legate'
require 'legate/auth'
require 'legate/auth/runner'
require 'legate/auth/schemes/oauth2'
require 'legate/tool_context'
require 'legate/web/server'
require 'launchy'
require 'securerandom'

# This example demonstrates the fiber-based authentication flow
# It shows how to:
# 1. Set up an authentication runner
# 2. Use the auth_session method within a tool
# 3. Handle authentication requests and responses
# 4. Launch a browser for OAuth2 authorization
# 5. Start a temporary web server to receive the OAuth2 callback

class ExampleTool < Legate::Tool::Base
  name :example_tool
  description 'Example tool demonstrating fiber-based authentication'
  version '1.0.0'

  parameter :action, type: :symbol, required: true,
                     description: 'Action to perform (call_api, handle_response, run_with_server)'
  parameter :request_id, type: :string, required: false,
                         description: 'The authentication request ID for handling responses'
  parameter :response_uri, type: :string, required: false,
                           description: 'The response URI from the OAuth2 callback'
  parameter :client_id, type: :string, required: false,
                        description: 'OAuth2 client ID'
  parameter :client_secret, type: :string, required: false,
                            description: 'OAuth2 client secret'

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
      # Run with a local server to automatically handle the OAuth2 callback
      run_with_local_server
    else
      raise Legate::ToolError, "Unknown action: #{parameters[:action]}"
    end
  end

  private

  def call_api_with_auth
    # Define an OAuth2 scheme
    oauth2_scheme = create_oauth2_scheme

    # Define a credential
    credential = create_credential

    # Start an authentication session
    # This will yield the fiber if authentication is needed
    token = context.auth_session(
      oauth2_scheme,
      credential,
      redirect_uri: 'http://localhost:3000/auth/callback'
    )

    # If we get here, we have a valid token
    if token
      # Simulate an API call with the token
      api_call_result = simulate_api_call(token)

      {
        status: :success,
        message: 'Successfully authenticated and called API',
        token_type: token.token_type,
        expires_in: token.expires_in,
        scope: token.scope,
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
    # Create a web server to handle the OAuth2 callback
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

  def create_oauth2_scheme
    Legate::Auth::Schemes::OAuth2.new(
      authorization_url: 'https://accounts.google.com/o/oauth2/auth',
      token_url: 'https://oauth2.googleapis.com/token',
      scopes: %w[email profile],
      use_pkce: true,
      additional_params: {
        prompt: 'consent',
        access_type: 'offline'
      }
    )
  end

  def create_credential
    client_id = parameters[:client_id] || ENV['OAUTH_CLIENT_ID'] || 'your-client-id'
    client_secret = parameters[:client_secret] || ENV['OAUTH_CLIENT_SECRET'] || 'your-client-secret'

    Legate::Auth::Credential.new(
      auth_type: :oauth2,
      client_id: client_id,
      client_secret: client_secret
    )
  end

  def simulate_api_call(token)
    # In a real application, you would make an actual API call using the token
    # This is just a simulation
    {
      api_name: 'Example API',
      called_at: Time.now.iso8601,
      authorization: "#{token.token_type} #{token.access_token[0..5]}...[truncated]"
    }
  end

  def create_callback_server
    # Create a simple web server to handle OAuth2 callbacks
    server = Legate::Web::Server.new(port: 3000)

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
        active_requests = context.instance_variable_get(:@auth_runner)&.instance_variable_get(:@active_coordinators)
        request_id = active_requests&.keys&.first

        if request_id
          # Handle the auth response
          result = context.handle_auth_response(request_id, { 'response_uri' => response_uri })

          # Show a success page
          res.status = 200
          res.body = '<html><body><h1>Authentication Successful</h1><p>You can close this window and return to the application.</p></body></html>'
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

      puts 'Waiting for OAuth2 callback...'
    else
      puts "Unhandled auth request type: #{auth_request[:auth_request][:type]}"
    end

    # Return nil to continue waiting for the callback
    nil
  end
end

# Register the tool
Legate.register_tool(ExampleTool)

# Example usage:
# 1. First call with action: :call_api
#    - This will start authentication and yield an auth request
# 2. Use the request_id from the first call and pass it along with a response_uri
#    - Call with action: :handle_response, request_id: "...", response_uri: "..."
# 3. Or use action: :run_with_server to launch a browser and handle the callback automatically
if $PROGRAM_NAME == __FILE__
  # Setup a session service for the example
  require 'legate/session_service/in_memory'
  session_service = Legate::SessionService::InMemory.new

  # Create a tool context with the session service
  context = Legate::ToolContext.new(session_service: session_service)

  # Create and run the tool
  tool = ExampleTool.new

  begin
    # Run with a local server to automatically handle the OAuth2 callback
    # This is the most user-friendly approach for a CLI tool
    if ARGV.include?('--with-server')
      result = tool.run(context, action: :run_with_server)
      puts "Result: #{result.inspect}"
    else
      # Attempt to call API - this will yield for authentication
      result = tool.run(context, action: :call_api)

      # The result will include auth_request if authentication is needed
      if result.is_a?(Hash) && result[:auth_request]
        puts 'Authentication required. Please visit:'
        puts result[:auth_request][:url] if result[:auth_request][:url]
        puts "\nAfter completing authentication, run:"
        puts "ruby #{__FILE__} --handle-response --request-id #{result[:request_id]} --response-uri 'PASTE_RESPONSE_URI_HERE'"
      else
        puts "Result: #{result.inspect}"
      end
    end
  rescue StandardError => e
    puts "Error: #{e.class}: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']

    if e.message.include?('Authentication session not available')
      puts "\nNote: This example requires proper OAuth2 credentials."
      puts 'You can provide them as environment variables:'
      puts "OAUTH_CLIENT_ID='your-client-id' OAUTH_CLIENT_SECRET='your-client-secret' ruby #{__FILE__} --with-server"
    end
  end
end
