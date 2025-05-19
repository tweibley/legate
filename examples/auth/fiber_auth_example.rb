# frozen_string_literal: true

require 'bundler/setup'
require 'adk'
require 'adk/auth'
require 'adk/auth/runner'
require 'adk/auth/schemes/oauth2'
require 'adk/tool_context'

# This example demonstrates the fiber-based authentication flow
# It shows how to:
# 1. Set up an authentication runner
# 2. Use the auth_session method within a tool
# 3. Handle authentication requests and responses

class ExampleTool < ADK::Tool::Base
  name :example_tool
  description "Example tool demonstrating fiber-based authentication"
  version "1.0.0"
  
  parameter :action, type: :symbol, required: true, 
            description: "Action to perform (call_api, handle_response)"
  parameter :request_id, type: :string, required: false,
            description: "The authentication request ID for handling responses"
  parameter :response_uri, type: :string, required: false,
            description: "The response URI from the OAuth2 callback"
  
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
    else
      raise ADK::ToolError, "Unknown action: #{parameters[:action]}"
    end
  end
  
  private
  
  def call_api_with_auth
    # Define an OAuth2 scheme
    oauth2_scheme = ADK::Auth::Schemes::OAuth2.new(
      authorization_url: 'https://accounts.google.com/o/oauth2/auth',
      token_url: 'https://oauth2.googleapis.com/token',
      scopes: ['email', 'profile'],
      use_pkce: true
    )
    
    # Define a credential
    credential = ADK::Auth::Credential.new(
      auth_type: :oauth2,
      client_id: 'your-client-id',
      client_secret: 'your-client-secret'
    )
    
    # Start an authentication session
    # This will yield the fiber if authentication is needed
    token = context.auth_session(
      oauth2_scheme,
      credential,
      redirect_uri: 'http://localhost:3000/auth/callback'
    )
    
    # If we get here, we have a valid token
    if token
      {
        status: :success,
        message: "Successfully authenticated",
        token_type: token.token_type,
        expires_in: token.expires_in,
        scope: token.scope
      }
    else
      { status: :error, message: "Failed to authenticate" }
    end
  end
  
  def handle_auth_response
    # Get required parameters
    request_id = parameters[:request_id]
    response_uri = parameters[:response_uri]
    
    unless request_id && response_uri
      raise ADK::ToolArgumentError, "Both request_id and response_uri are required"
    end
    
    # Create a response object
    response = { 'response_uri' => response_uri }
    
    # Handle the authentication response
    result = context.handle_auth_response(request_id, response)
    
    # Return the result
    {
      status: result[:status],
      message: result[:status] == :completed ? "Authentication completed" : "Authentication in progress",
      details: result
    }
  end
end

# Register the tool
ADK.register_tool(ExampleTool)

# Example usage:
# 1. First call with action: :call_api
#    - This will start authentication and yield an auth request
# 2. Use the request_id from the first call and pass it along with a response_uri
#    - Call with action: :handle_response, request_id: "...", response_uri: "..."
if $PROGRAM_NAME == __FILE__
  # Setup a session service for the example
  require 'adk/session_service/memory'
  session_service = ADK::SessionService::Memory.new
  
  # Create a tool context with the session service
  context = ADK::ToolContext.new(session_service: session_service)
  
  # Create and run the tool
  tool = ExampleTool.new
  
  begin
    # Attempt to call API - this will yield for authentication
    result = tool.run(context, action: :call_api)
    puts "Result: #{result.inspect}"
  rescue => e
    if e.message.include?('Authentication session not available')
      puts "Note: This example requires a real implementation that can handle the authentication flow."
      puts "In a real application, you would handle the auth request and call the tool again with action: :handle_response"
    else
      puts "Error: #{e.class}: #{e.message}"
    end
  end
end 