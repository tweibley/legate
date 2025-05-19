#!/usr/bin/env ruby
# frozen_string_literal: true

require 'adk-ruby'
require 'adk/auth/schemes/oauth2'
require 'sinatra/base'
require 'webrick'
require 'logger'
require 'json'

class GitHubUserTool < ADK::Tool::Base
  name 'github_user'
  description 'Get information about a GitHub user using OAuth2 authentication'
  display_name 'GitHub User'
  
  parameter :username, type: :string, description: 'GitHub username to get information about'
  
  def call(username:)
    unless secured_credential
      raise ADK::Tool::ExecutionError, 'Authentication required. Please run the tool with authentication enabled.'
    end
    
    # Get user information from GitHub API
    response = ADK::Auth.apply_authentication(
      {
        method: :get,
        url: "https://api.github.com/users/#{username}",
        headers: {
          'Accept' => 'application/vnd.github.v3+json',
          'User-Agent' => 'ADK-Ruby-Example'
        }
      },
      secured_credential
    )
    
    ADK::Tool::Response.success(JSON.parse(response.body))
  rescue Excon::Error => e
    ADK::Tool::Response.error("GitHub API error: #{e.message}")
  end
end

# Create the OAuth callback server for the OAuth2 flow
class OAuthCallbackServer < Sinatra::Base
  set :port, 3000
  
  get '/oauth/callback' do
    # Handle the OAuth callback
    ADK::Auth.handle_oauth_callback(request.url)
    
    <<~HTML
      <html>
        <body>
          <h1>Authorization Successful</h1>
          <p>You can close this window and return to the application.</p>
          <script>window.close()</script>
        </body>
      </html>
    HTML
  end
end

# Main example code
def run_example
  # Configure logging
  ADK.configure do |config|
    config.logger = Logger.new($stdout)
    config.logger.level = Logger::INFO
  end
  
  # Start the callback server in a thread
  Thread.new do
    OAuthCallbackServer.run!
  end
  
  # Define the OAuth2 provider ID
  provider_id = 'github'
  
  # Create the OAuth2 scheme
  scheme = ADK::Auth::Schemes::OAuth2.new(
    authorization_url: 'https://github.com/login/oauth/authorize',
    token_url: 'https://github.com/login/oauth/access_token',
    scopes: ['user:email', 'read:user']
  )
  
  # Create the credential with client information
  # In a real application, you would load these from environment variables or a secure store
  credential = ADK::Auth::Credential.new(
    auth_type: :oauth2,
    client_id: 'YOUR_GITHUB_CLIENT_ID',
    client_secret: 'YOUR_GITHUB_CLIENT_SECRET'
  )
  
  # Register the tool
  ADK::Tool::Registry.register(GitHubUserTool)
  
  # Create a session
  session = ADK::SessionService::Memory.new
  
  # Start the OAuth2 flow
  auth_uri = ADK::Auth.start_oauth_flow(
    provider_id,
    scheme,
    credential,
    'http://localhost:3000/oauth/callback'
  )
  
  puts "Please open the following URL in your browser to authorize the application:"
  puts auth_uri
  puts "Waiting for authorization..."
  
  # Wait for the callback and exchange the code for tokens
  exchanged_credential = ADK::Auth.complete_oauth_flow(provider_id)
  
  puts "Successfully authenticated with GitHub!"
  puts "Access token: #{exchanged_credential.access_token[0..5]}... (expires in #{exchanged_credential.expires_in} seconds)"
  
  # Create a runner with the secured credential
  runner = ADK::Runner.new(session: session)
  
  # Run the tool with authentication
  result = runner.run_tool(
    tool_name: 'github_user',
    parameters: { username: 'octocat' },
    auth_credential: exchanged_credential
  )
  
  puts "User information:"
  puts JSON.pretty_generate(result.data)
  
  # Refresh the token if it's about to expire
  if exchanged_credential.refreshable? && exchanged_credential.expired?(300)
    puts "Refreshing the access token..."
    refreshed_credential = ADK::Auth.refresh_token(provider_id)
    puts "Token refreshed successfully!"
  end
end

run_example if $PROGRAM_NAME == __FILE__ 