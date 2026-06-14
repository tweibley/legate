# Custom Authentication Flow

## Overview

While the Legate Ruby library provides built-in support for common authentication schemes, you may need to implement custom authentication flows for APIs with unique requirements. This guide explains how to create custom authentication flows using the Legate's authentication framework.

## When to Use Custom Authentication Flows

Consider implementing a custom authentication flow in the following scenarios:

- The API uses a non-standard authentication mechanism not covered by the built-in schemes
- You need to modify the standard authentication flow with additional steps or parameters
- You need to implement a proprietary authentication protocol specific to your API
- You want to combine multiple authentication mechanisms into a single flow

## Building Custom Authentication Schemes

### Creating a Custom Scheme Class

Custom authentication schemes should inherit from the `Legate::Auth::Scheme` base class:

```ruby
module Legate
  module Auth
    module Schemes
      class CustomScheme < Legate::Auth::Scheme
        attr_reader :custom_param, :auth_url, :token_url
        
        def initialize(custom_param:, auth_url:, token_url:)
          @custom_param = custom_param
          @auth_url = auth_url
          @token_url = token_url
        end
        
        # Define the authentication type
        def auth_type
          :custom
        end
        
        # Define how to apply the credentials to a request
        def apply_to_request(request, credential, tokens = nil)
          if tokens
            # Apply obtained tokens to the request
            request[:headers] ||= {}
            request[:headers]['Authorization'] = "Custom #{tokens[:access_token]}"
          elsif credential
            # Apply initial credentials to the request
            request[:headers] ||= {}
            request[:headers]['X-Custom-Auth'] = credential.custom_key
          end
          request
        end
        
        # Define how to check if tokens are valid
        def tokens_valid?(tokens)
          return false unless tokens
          return false unless tokens[:access_token]
          return false if tokens[:expires_at] && Time.now.to_i >= tokens[:expires_at]
          true
        end
        
        # Define token refresh logic
        def refresh_tokens(credential, tokens)
          # Implement token refresh logic
          # Return new tokens or raise an error
        end
      end
    end
  end
end
```

### Key Methods to Implement

When creating a custom authentication scheme, implement these key methods:

| Method | Description | Return Value |
|--------|-------------|--------------|
| `auth_type` | Identifies the authentication type | Symbol (e.g., `:custom`) |
| `apply_to_request` | Applies credentials or tokens to requests | Modified request hash |
| `tokens_valid?` | Checks if tokens are valid | Boolean |
| `refresh_tokens` | Refreshes expired tokens | Hash of new tokens or raises error |

## Implementing Interactive Authentication

For interactive authentication flows (similar to OAuth2), you'll need to implement both the client-side and server-side components.

### Step 1: Creating an Interactive Scheme

```ruby
class CustomInteractiveScheme < Legate::Auth::Scheme
  attr_reader :auth_url, :token_url
  
  def initialize(auth_url:, token_url:)
    @auth_url = auth_url
    @token_url = token_url
  end
  
  def auth_type
    :custom_interactive
  end
  
  # Generate the authorization URL for the interactive flow
  def generate_auth_url(credential, redirect_uri, state)
    uri = URI.parse(@auth_url)
    params = {
      'client_id' => credential.client_id,
      'redirect_uri' => redirect_uri,
      'state' => state,
      'response_type' => 'code',
      'custom_param' => 'custom_value'
    }
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end
  
  # Exchange the auth code for tokens
  def exchange_auth_code(credential, code, redirect_uri)
    response = Excon.post(
      @token_url,
      headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
      body: URI.encode_www_form(
        'grant_type' => 'authorization_code',
        'code' => code,
        'redirect_uri' => redirect_uri,
        'client_id' => credential.client_id,
        'client_secret' => credential.client_secret
      )
    )
    
    if response.status != 200
      raise Legate::Auth::TokenExchangeError, "Failed to exchange code: #{response.body}"
    end
    
    parse_token_response(response.body)
  end
  
  # Parse the token response into a standard format
  def parse_token_response(response_body)
    data = JSON.parse(response_body)
    {
      access_token: data['access_token'],
      refresh_token: data['refresh_token'],
      token_type: data['token_type'] || 'Bearer',
      expires_at: data['expires_in'] ? Time.now.to_i + data['expires_in'].to_i : nil,
      scope: data['scope']
    }
  end
  
  # Apply tokens to requests
  def apply_to_request(request, credential, tokens = nil)
    if tokens
      request[:headers] ||= {}
      request[:headers]['Authorization'] = "#{tokens[:token_type]} #{tokens[:access_token]}"
    end
    request
  end
  
  # Check if tokens are valid
  def tokens_valid?(tokens)
    return false unless tokens
    return false unless tokens[:access_token]
    return false if tokens[:expires_at] && Time.now.to_i >= tokens[:expires_at]
    true
  end
  
  # Refresh tokens
  def refresh_tokens(credential, tokens)
    return nil unless tokens[:refresh_token]
    
    response = Excon.post(
      @token_url,
      headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
      body: URI.encode_www_form(
        'grant_type' => 'refresh_token',
        'refresh_token' => tokens[:refresh_token],
        'client_id' => credential.client_id,
        'client_secret' => credential.client_secret
      )
    )
    
    if response.status != 200
      raise Legate::Auth::TokenRefreshError, "Failed to refresh token: #{response.body}"
    end
    
    # Merge the new tokens with the existing tokens
    refresh_data = parse_token_response(response.body)
    tokens.merge(refresh_data)
  end
end
```

### Step 2: Creating a Custom Authentication Coordinator

For interactive flows, create a coordinator to handle the authentication flow:

```ruby
module Legate
  module Auth
    module Coordinators
      class CustomInteractiveCoordinator
        def initialize(scheme, credential)
          @scheme = scheme
          @credential = credential
        end
        
        # Handle the auth request phase
        def handle_auth_request(config)
          # Generate state for CSRF protection
          state = SecureRandom.hex(16)
          
          # Generate the auth URL
          auth_url = @scheme.generate_auth_url(
            @credential,
            config.redirect_uri,
            state
          )
          
          # Return the auth URL and state
          {
            auth_url: auth_url,
            state: state
          }
        end
        
        # Handle the auth response phase
        def handle_auth_response(config)
          # Parse the auth response URI
          uri = URI.parse(config.auth_response_uri)
          params = CGI.parse(uri.query || '')
          
          # Extract the authorization code
          code = params['code']&.first
          unless code
            raise Legate::Auth::TokenExchangeError, "Missing authorization code in response"
          end
          
          # Exchange the code for tokens
          tokens = @scheme.exchange_auth_code(
            @credential,
            code,
            config.redirect_uri
          )
          
          # Return the tokens
          tokens
        end
      end
    end
  end
end
```

### Step 3: Using the Custom Scheme in Tools

```ruby
# Create custom scheme and credential
custom_scheme = CustomInteractiveScheme.new(
  auth_url: 'https://auth.example.com/authorize',
  token_url: 'https://auth.example.com/token'
)

# Note: a custom credential still requires a valid auth_type. If your scheme
# doesn't map to a built-in type, :basic (with username/password) or one of the
# existing types can serve as the carrier for your client credentials.
custom_credential = Legate::Auth::Credential.new(
  auth_type: :oauth2,
  client_id: ENV['CUSTOM_CLIENT_ID'],
  client_secret: ENV['CUSTOM_CLIENT_SECRET']
)

# Create a tool that uses the custom scheme and coordinator
class CustomApiTool < Legate::Tool
  tool_description 'A tool that uses custom authentication'

  def perform_execution(params, context)
    scheme = CustomInteractiveScheme.new(
      auth_url: 'https://auth.example.com/authorize',
      token_url: 'https://auth.example.com/token'
    )
    credential = Legate::Auth::Credential.new(
      auth_type: :oauth2,
      client_id: ENV['CUSTOM_CLIENT_ID'],
      client_secret: ENV['CUSTOM_CLIENT_SECRET']
    )

    # Drive interactive auth via context.with_authentication, which yields the
    # auth request to your application for handling (see ToolContextExtension).
    context.with_authentication do
      # Once tokens are available, build a request and apply the scheme's tokens.
      # Here we illustrate applying obtained tokens directly:
      tokens = { access_token: 'obtained-access-token', token_type: 'Bearer' }
      request = scheme.apply_to_request({ headers: {} }, credential, tokens)

      conn = Excon.new('https://api.example.com')
      response = conn.get(path: '/data', headers: request[:headers])
      { status: :success, result: JSON.parse(response.body) }
    end
  end
end
```

## Testing Custom Authentication Flows

### Unit Testing Schemes

```ruby
RSpec.describe CustomInteractiveScheme do
  let(:scheme) do
    CustomInteractiveScheme.new(
      auth_url: 'https://auth.example.com/authorize',
      token_url: 'https://auth.example.com/token'
    )
  end
  
  let(:credential) do
    Legate::Auth::Credential.new(
      auth_type: :oauth2,
      client_id: 'test_client_id',
      client_secret: 'test_client_secret'
    )
  end
  
  describe '#generate_auth_url' do
    it 'generates a valid authorization URL' do
      url = scheme.generate_auth_url(credential, 'https://callback.example.com', 'state123')
      uri = URI.parse(url)
      params = CGI.parse(uri.query)
      
      expect(uri.host).to eq('auth.example.com')
      expect(uri.path).to eq('/authorize')
      expect(params['client_id']).to eq(['test_client_id'])
      expect(params['redirect_uri']).to eq(['https://callback.example.com'])
      expect(params['state']).to eq(['state123'])
      expect(params['response_type']).to eq(['code'])
    end
  end
  
  describe '#apply_to_request' do
    it 'applies tokens to the request' do
      tokens = {
        access_token: 'test_access_token',
        token_type: 'Bearer'
      }
      
      request = {}
      modified_request = scheme.apply_to_request(request, credential, tokens)
      
      expect(modified_request[:headers]['Authorization']).to eq('Bearer test_access_token')
    end
  end
  
  # Add tests for other methods
end
```

### Integration Testing

> The runner harness below is illustrative pseudo-code for an end-to-end test.
> Adapt it to however your application drives tools and supplies the auth
> response (e.g. through `context.with_authentication`).

```ruby
RSpec.describe 'Custom Authentication Integration' do
  let(:scheme) do
    CustomInteractiveScheme.new(
      auth_url: 'https://auth.example.com/authorize',
      token_url: 'https://auth.example.com/token'
    )
  end
  
  let(:credential) do
    Legate::Auth::Credential.new(
      auth_type: :oauth2,
      client_id: 'test_client_id',
      client_secret: 'test_client_secret'
    )
  end
  
  let(:runner) { Legate::Runner.new }
  let(:tool) { CustomApiTool.new }
  
  before do
    # Mock the token endpoint
    stub_request(:post, 'https://auth.example.com/token')
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: {
          access_token: 'test_access_token',
          refresh_token: 'test_refresh_token',
          token_type: 'Bearer',
          expires_in: 3600
        }.to_json
      )
    
    # Mock the API endpoint
    stub_request(:get, 'https://api.example.com/data')
      .with(headers: { 'Authorization' => 'Bearer test_access_token' })
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: { success: true, data: [1, 2, 3] }.to_json
      )
  end
  
  it 'successfully completes the authentication flow' do
    # Mock the auth response by setting up the Fiber directly
    # In a real application, this would come from the user interaction
    runner.auth_response = Legate::Auth::Config.new(
      auth_response_uri: 'https://callback.example.com?code=test_auth_code&state=test_state',
      redirect_uri: 'https://callback.example.com'
    )
    
    # Run the tool
    result = runner.run(tool)
    
    # Check the result
    expect(result[:status]).to eq('success')
    expect(result[:result]).to eq({ 'success' => true, 'data' => [1, 2, 3] })
  end
end
```

## Handling Edge Cases

### Handling Authentication Errors

Ensure your custom authentication flow properly handles various error scenarios:

```ruby
def exchange_auth_code(credential, code, redirect_uri)
  response = Excon.post(
    @token_url,
    headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
    body: URI.encode_www_form(
      'grant_type' => 'authorization_code',
      'code' => code,
      'redirect_uri' => redirect_uri,
      'client_id' => credential.client_id,
      'client_secret' => credential.client_secret
    )
  )
  
  case response.status
  when 200
    parse_token_response(response.body)
  when 400
    error_data = JSON.parse(response.body) rescue { 'error' => 'invalid_request' }
    handle_error(error_data)
  when 401
    raise Legate::Auth::CredentialError, "Invalid client credentials"
  else
    raise Legate::Auth::TokenExchangeError, "Failed to exchange code: #{response.body}"
  end
end

def handle_error(error_data)
  error = error_data['error']
  
  case error
  when 'invalid_grant'
    raise Legate::Auth::TokenExchangeError, "Invalid authorization code"
  when 'invalid_client'
    raise Legate::Auth::CredentialError, "Invalid client credentials"
  when 'invalid_request'
    raise Legate::Auth::TokenExchangeError, "Invalid request: #{error_data['error_description']}"
  else
    raise Legate::Auth::TokenExchangeError, "Authentication error: #{error_data['error_description'] || error}"
  end
end
```

### Implementing Non-Standard Token Refresh

If your API has a non-standard token refresh mechanism:

```ruby
def refresh_tokens(credential, tokens)
  # Custom refresh logic
  response = Excon.post(
    @token_url,
    headers: {
      'Content-Type' => 'application/x-www-form-urlencoded',
      'Authorization' => "Basic #{Base64.strict_encode64("#{credential.client_id}:#{credential.client_secret}")}"
    },
    body: URI.encode_www_form(
      'grant_type' => 'custom_refresh',
      'refresh_token' => tokens[:refresh_token],
      'custom_param' => 'custom_value'
    )
  )
  
  if response.status != 200
    raise Legate::Auth::TokenRefreshError, "Failed to refresh token: #{response.body}"
  end
  
  # Parse and return the refreshed tokens
  refresh_data = parse_token_response(response.body)
  
  # Preserve the original refresh token if a new one isn't provided
  refresh_data[:refresh_token] ||= tokens[:refresh_token]
  
  refresh_data
end
```

## Best Practices

1. **Security First**: Implement proper security measures, including CSRF protection, secure token storage, and HTTPS for all requests
2. **Error Handling**: Implement comprehensive error handling for all authentication steps
3. **Logging**: Add appropriate logging to help debug authentication issues
4. **Testing**: Write thorough tests for both normal and error cases
5. **Documentation**: Document your custom authentication scheme thoroughly
6. **Token Management**: Implement proper token lifecycle management (expiration, refresh)
7. **Follow Standards**: When possible, follow existing standards and conventions

## Related Topics
- [Authentication Configuration](./configuration)
- [Token Lifecycle Management](./token_lifecycle)
- [Secure Credential Storage](./secure_storage)
- [`Legate::Auth::Scheme` API Reference](../api_reference/scheme)
- [`Legate::ToolContext` Authentication Extensions](../api_reference/tool_context_extension) 