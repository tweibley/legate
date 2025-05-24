#!/usr/bin/env ruby
# frozen_string_literal: true

# Custom Authentication Flows Example
#
# This example demonstrates advanced authentication patterns including:
# - Creating custom authentication schemes
# - Multi-step authentication flows  
# - Custom authentication middleware
# - Conditional authentication based on request properties
# - Authentication delegation and chaining
# - Custom token formats and validation
#
# Usage:
#   ruby examples/auth/custom_auth_flows_example.rb [--flow basic|digest|multi_step|conditional]

require 'bundler/setup'
require 'adk'
require 'adk/auth'
require 'base64'
require 'digest'
require 'optparse'
require 'securerandom'

# Parse command line options
options = {
  flow: 'basic',
  verbose: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{__FILE__} [options]"
  
  opts.on("--flow FLOW", ["basic", "digest", "multi_step", "conditional"], "Authentication flow to demonstrate") do |flow|
    options[:flow] = flow
  end
  
  opts.on("--verbose", "Enable verbose output") do
    options[:verbose] = true
  end
  
  opts.on("--help", "Show this help") do
    puts opts
    exit
  end
end.parse!

puts "=== Custom Authentication Flows Example ==="
puts "Flow: #{options[:flow]}"
puts

# 1. Custom Basic Authentication Scheme
# Extends the basic auth pattern with custom headers and validation
class CustomBasicAuthScheme < ADK::Auth::Scheme
  def initialize(realm: 'Protected Area', custom_header: nil)
    super()
    @realm = realm
    @custom_header = custom_header
  end

  def scheme_type
    :custom_basic
  end

  def apply_to_request(credential, params = {})
    username = credential[:username] || credential[:username, resolve_env: true]
    password = credential[:password] || credential[:password, resolve_env: true]
    
    raise ADK::Auth::Error, "Username is required for custom basic auth" unless username
    raise ADK::Auth::Error, "Password is required for custom basic auth" unless password

    # Create basic auth header
    encoded = Base64.strict_encode64("#{username}:#{password}")
    
    headers = params[:headers] || {}
    headers['Authorization'] = "Basic #{encoded}"
    
    # Add custom header if specified
    if @custom_header
      headers[@custom_header] = "Basic-#{@realm}"
    end
    
    # Add client identification
    headers['User-Agent'] = "ADK-CustomAuth/1.0"
    
    { headers: headers }
  end

  def to_h
    {
      scheme_type: scheme_type,
      realm: @realm,
      custom_header: @custom_header
    }
  end
end

# 2. Custom Digest Authentication Scheme
# Implements digest authentication with custom challenge handling
class CustomDigestAuthScheme < ADK::Auth::Scheme
  def initialize(realm: 'Protected Area')
    super()
    @realm = realm
    @nonce_count = 0
  end

  def scheme_type
    :custom_digest
  end

  def apply_to_request(credential, params = {})
    username = credential[:username] || credential[:username, resolve_env: true]
    password = credential[:password] || credential[:password, resolve_env: true]
    
    raise ADK::Auth::Error, "Username is required for digest auth" unless username
    raise ADK::Auth::Error, "Password is required for digest auth" unless password

    # Simulate digest challenge (in real implementation this would come from a 401 response)
    nonce = params[:nonce] || SecureRandom.hex(16)
    uri = params[:uri] || '/'
    method = params[:method] || 'GET'
    
    @nonce_count += 1
    nc = sprintf("%08x", @nonce_count)
    cnonce = SecureRandom.hex(8)
    
    # Calculate digest response
    ha1 = Digest::MD5.hexdigest("#{username}:#{@realm}:#{password}")
    ha2 = Digest::MD5.hexdigest("#{method}:#{uri}")
    response = Digest::MD5.hexdigest("#{ha1}:#{nonce}:#{nc}:#{cnonce}:auth:#{ha2}")
    
    # Build digest header
    digest_header = [
      "Digest username=\"#{username}\"",
      "realm=\"#{@realm}\"",
      "nonce=\"#{nonce}\"",
      "uri=\"#{uri}\"",
      "response=\"#{response}\"",
      "algorithm=MD5",
      "qop=auth",
      "nc=#{nc}",
      "cnonce=\"#{cnonce}\""
    ].join(', ')

    headers = params[:headers] || {}
    headers['Authorization'] = digest_header
    
    { headers: headers }
  end

  def to_h
    {
      scheme_type: scheme_type,
      realm: @realm,
      nonce_count: @nonce_count
    }
  end
end

# 3. Multi-Step Authentication Scheme
# Demonstrates a multi-step authentication flow with state management
class MultiStepAuthScheme < ADK::Auth::Scheme
  def initialize
    super()
    @auth_state = {}
  end

  def scheme_type
    :multi_step
  end

  def apply_to_request(credential, params = {})
    step = params[:step] || 1
    session_id = params[:session_id] || SecureRandom.hex(16)
    
    case step
    when 1
      # Step 1: Initial authentication
      perform_step_1(credential, session_id)
    when 2
      # Step 2: Second factor
      perform_step_2(credential, session_id, params)
    when 3
      # Step 3: Final token
      perform_step_3(credential, session_id, params)
    else
      raise ADK::Auth::Error, "Invalid authentication step: #{step}"
    end
  end

  def to_h
    {
      scheme_type: scheme_type,
      active_sessions: @auth_state.keys.length
    }
  end

  private

  def perform_step_1(credential, session_id)
    username = credential[:username] || credential[:username, resolve_env: true]
    password = credential[:password] || credential[:password, resolve_env: true]
    
    raise ADK::Auth::Error, "Username required for step 1" unless username
    raise ADK::Auth::Error, "Password required for step 1" unless password

    # Simulate password validation
    if username && password
      # Store session state
      @auth_state[session_id] = {
        username: username,
        step: 1,
        timestamp: Time.now,
        verified_factors: []
      }
      
      step_1_token = Base64.strict_encode64("step1:#{session_id}:#{username}")
      
      {
        headers: {
          'X-Auth-Step' => '1',
          'X-Auth-Token' => step_1_token,
          'X-Session-ID' => session_id
        },
        next_step: 2,
        session_id: session_id
      }
    else
      raise ADK::Auth::Error, "Invalid credentials"
    end
  end

  def perform_step_2(credential, session_id, params)
    session = @auth_state[session_id]
    raise ADK::Auth::Error, "Invalid session" unless session
    raise ADK::Auth::Error, "Must complete step 1 first" unless session[:step] >= 1

    # Second factor (could be TOTP, SMS, etc.)
    second_factor = credential[:second_factor] || params[:second_factor] || '123456'
    
    # Simulate second factor validation
    if second_factor == '123456'  # Demo validation
      session[:step] = 2
      session[:verified_factors] << 'password'
      session[:verified_factors] << 'second_factor'
      
      step_2_token = Base64.strict_encode64("step2:#{session_id}:#{session[:username]}")
      
      {
        headers: {
          'X-Auth-Step' => '2',
          'X-Auth-Token' => step_2_token,
          'X-Session-ID' => session_id
        },
        next_step: 3,
        session_id: session_id
      }
    else
      raise ADK::Auth::Error, "Invalid second factor"
    end
  end

  def perform_step_3(credential, session_id, params)
    session = @auth_state[session_id]
    raise ADK::Auth::Error, "Invalid session" unless session
    raise ADK::Auth::Error, "Must complete step 2 first" unless session[:step] >= 2

    # Generate final access token
    session[:step] = 3
    session[:completed_at] = Time.now
    
    final_token = Base64.strict_encode64("final:#{session_id}:#{session[:username]}:#{Time.now.to_i}")
    
    {
      headers: {
        'Authorization' => "Bearer #{final_token}",
        'X-Auth-Complete' => 'true'
      },
      access_token: final_token,
      session_id: session_id,
      authenticated: true
    }
  end
end

# 4. Conditional Authentication Scheme
# Applies different authentication methods based on request context
class ConditionalAuthScheme < ADK::Auth::Scheme
  def initialize
    super()
    @api_key_scheme = ADK::Auth::Schemes::ApiKey.new
    @bearer_scheme = ADK::Auth::Schemes::HTTPBearer.new
  end

  def scheme_type
    :conditional
  end

  def apply_to_request(credential, params = {})
    # Determine authentication method based on request context
    auth_method = determine_auth_method(params)
    
    case auth_method
    when :api_key
      puts "Using API Key authentication for this request"
      @api_key_scheme.apply_to_request(credential, params)
    when :bearer
      puts "Using Bearer token authentication for this request"  
      @bearer_scheme.apply_to_request(credential, params)
    when :none
      puts "No authentication required for this request"
      { headers: {} }
    else
      raise ADK::Auth::Error, "No suitable authentication method available"
    end
  end

  def to_h
    {
      scheme_type: scheme_type,
      available_methods: [:api_key, :bearer, :none]
    }
  end

  private

  def determine_auth_method(params)
    url = params[:url] || ''
    method = params[:method] || 'GET'
    headers = params[:headers] || {}
    
    # Public endpoints don't need auth
    return :none if url.include?('/public/') || url.include?('/health')
    
    # API endpoints prefer API key
    return :api_key if url.include?('/api/') && method != 'GET'
    
    # Authenticated endpoints use bearer tokens
    return :bearer if headers['Accept']&.include?('application/json')
    
    # Default to API key
    :api_key
  end
end

# 5. Custom Authentication Middleware
# Demonstrates custom middleware that can handle multiple schemes
class CustomAuthMiddleware
  def initialize(app, schemes: {}, default_scheme: nil)
    @app = app
    @schemes = schemes
    @default_scheme = default_scheme
  end

  def call(env)
    # Extract request information
    request_path = env['PATH_INFO'] || '/'
    request_method = env['REQUEST_METHOD'] || 'GET'
    
    # Determine which scheme to use
    scheme_name = determine_scheme(request_path, request_method)
    scheme = @schemes[scheme_name] || @schemes[@default_scheme]
    
    if scheme
      # Apply authentication
      begin
        auth_result = scheme.apply_to_request(
          get_credential_for_scheme(scheme_name),
          {
            url: request_path,
            method: request_method,
            headers: extract_headers(env)
          }
        )
        
        # Add auth headers to the request
        if auth_result[:headers]
          auth_result[:headers].each do |key, value|
            env["HTTP_#{key.upcase.tr('-', '_')}"] = value
          end
        end
        
        puts "Applied #{scheme_name} authentication to #{request_method} #{request_path}"
      rescue ADK::Auth::Error => e
        puts "Authentication failed: #{e.message}"
        return [401, {'Content-Type' => 'text/plain'}, ['Authentication required']]
      end
    end

    @app.call(env)
  end

  private

  def determine_scheme(path, method)
    return :multi_step if path.include?('/secure/')
    return :conditional if path.include?('/api/')
    return :custom_digest if path.include?('/digest/')
    @default_scheme
  end

  def get_credential_for_scheme(scheme_name)
    # In a real application, you'd retrieve appropriate credentials
    case scheme_name
    when :custom_basic, :custom_digest, :multi_step
      ADK::Auth::Credential.new(
        auth_type: :basic,
        username: 'demo_user',
        password: 'demo_pass'
      )
    when :conditional
      ADK::Auth::Credential.new(
        auth_type: :api_key,
        api_key: 'demo_api_key_123'
      )
    else
      ADK::Auth::Credential.new(
        auth_type: :api_key,
        api_key: 'default_key_456'
      )
    end
  end

  def extract_headers(env)
    headers = {}
    env.each do |key, value|
      if key.start_with?('HTTP_')
        header_name = key[5..-1].split('_').map(&:capitalize).join('-')
        headers[header_name] = value
      end
    end
    headers
  end
end

# Demonstration based on selected flow
case options[:flow]
when 'basic'
  puts "=== Custom Basic Authentication Demo ==="
  
  scheme = CustomBasicAuthScheme.new(
    realm: 'Demo Protected Area',
    custom_header: 'X-Custom-Auth'
  )
  
  credential = ADK::Auth::Credential.new(
    auth_type: :basic,
    username: 'demo_user',
    password: 'secret_password'
  )
  
  puts "Created custom basic auth scheme with realm: 'Demo Protected Area'"
  puts "Scheme type: #{scheme.scheme_type}"
  puts
  
  # Apply authentication
  result = scheme.apply_to_request(credential)
  puts "Authentication applied successfully!"
  puts "Headers added:"
  result[:headers].each { |k, v| puts "  #{k}: #{v}" }

when 'digest'
  puts "=== Custom Digest Authentication Demo ==="
  
  scheme = CustomDigestAuthScheme.new(realm: 'Digest Protected')
  
  credential = ADK::Auth::Credential.new(
    auth_type: :basic,
    username: 'digest_user',
    password: 'digest_pass'
  )
  
  puts "Created custom digest auth scheme"
  puts "Scheme type: #{scheme.scheme_type}"
  puts
  
  # Simulate multiple requests with digest auth
  3.times do |i|
    puts "Request #{i + 1}:"
    result = scheme.apply_to_request(
      credential, 
      {
        uri: "/protected/resource#{i + 1}",
        method: 'GET',
        nonce: SecureRandom.hex(16)
      }
    )
    
    auth_header = result[:headers]['Authorization']
    puts "  Authorization: #{auth_header[0..80]}..." if auth_header.length > 80
    puts
  end

when 'multi_step'
  puts "=== Multi-Step Authentication Demo ==="
  
  scheme = MultiStepAuthScheme.new
  
  credential = ADK::Auth::Credential.new(
    auth_type: :basic,
    username: 'multi_user',
    password: 'multi_pass',
    second_factor: '123456'
  )
  
  puts "Created multi-step auth scheme"
  puts "Scheme type: #{scheme.scheme_type}"
  puts
  
  session_id = nil
  
  # Step 1
  puts "Step 1: Initial authentication"
  result1 = scheme.apply_to_request(credential, { step: 1 })
  session_id = result1[:session_id]
  puts "  Next step: #{result1[:next_step]}"
  puts "  Session ID: #{session_id}"
  puts "  Headers: #{result1[:headers]}"
  puts
  
  # Step 2
  puts "Step 2: Second factor authentication"
  result2 = scheme.apply_to_request(credential, { step: 2, session_id: session_id })
  puts "  Next step: #{result2[:next_step]}"
  puts "  Headers: #{result2[:headers]}"
  puts
  
  # Step 3
  puts "Step 3: Final token generation"
  result3 = scheme.apply_to_request(credential, { step: 3, session_id: session_id })
  puts "  Authenticated: #{result3[:authenticated]}"
  puts "  Access token: #{result3[:access_token][0..20]}..."
  puts "  Headers: #{result3[:headers]}"

when 'conditional'
  puts "=== Conditional Authentication Demo ==="
  
  scheme = ConditionalAuthScheme.new
  
  # Create a credential that can work with multiple auth types
  credential = ADK::Auth::Credential.new(
    auth_type: :api_key,
    api_key: 'demo_api_key_789',
    bearer_token: 'demo_bearer_token_456'
  )
  
  puts "Created conditional auth scheme"
  puts "Scheme type: #{scheme.scheme_type}"
  puts
  
  # Test different request contexts
  test_requests = [
    { url: '/public/info', method: 'GET', description: 'Public endpoint' },
    { url: '/api/users', method: 'POST', description: 'API endpoint (non-GET)' },
    { url: '/dashboard', method: 'GET', headers: { 'Accept' => 'application/json' }, description: 'JSON API request' },
    { url: '/health', method: 'GET', description: 'Health check endpoint' },
    { url: '/api/data', method: 'GET', description: 'API endpoint (GET)' }
  ]
  
  test_requests.each do |req|
    puts "Testing: #{req[:description]}"
    puts "  #{req[:method]} #{req[:url]}"
    
    begin
      result = scheme.apply_to_request(credential, req)
      puts "  Result: #{result[:headers].any? ? result[:headers] : 'No authentication required'}"
    rescue => e
      puts "  Error: #{e.message}"
    end
    puts
  end

else
  puts "Unknown flow: #{options[:flow]}"
  exit 1
end

# Custom middleware demonstration
puts "\n=== Custom Authentication Middleware Demo ==="

# Create a simple WSGI-style app for demonstration
demo_app = lambda do |env|
  path = env['PATH_INFO']
  method = env['REQUEST_METHOD']
  [200, {'Content-Type' => 'text/plain'}, ["Success: #{method} #{path}"]]
end

# Create custom middleware with multiple schemes
middleware = CustomAuthMiddleware.new(
  demo_app,
  schemes: {
    custom_basic: CustomBasicAuthScheme.new,
    custom_digest: CustomDigestAuthScheme.new,
    multi_step: MultiStepAuthScheme.new,
    conditional: ConditionalAuthScheme.new
  },
  default_scheme: :custom_basic
)

# Simulate requests through the middleware
test_paths = [
  ['GET', '/public/info'],
  ['GET', '/api/data'],
  ['POST', '/secure/upload'],
  ['GET', '/digest/protected']
]

puts "Simulating requests through custom middleware:"
test_paths.each do |method, path|
  puts "\n#{method} #{path}:"
  env = {
    'REQUEST_METHOD' => method,
    'PATH_INFO' => path,
    'HTTP_ACCEPT' => 'application/json'
  }
  
  status, headers, body = middleware.call(env)
  puts "  Status: #{status}"
  puts "  Response: #{body.first}" if body.first
end

puts "\n=== Custom Authentication Flows Demo Complete ==="
puts "\nKey concepts demonstrated:"
puts "• Custom authentication scheme implementation"
puts "• Multi-step authentication workflows"
puts "• Conditional authentication based on request context"
puts "• Custom authentication middleware"
puts "• State management in authentication flows"
puts "• Integration of multiple authentication methods"
puts "\nThese patterns can be used to implement complex authentication"
puts "requirements that go beyond standard OAuth2/API key patterns." 