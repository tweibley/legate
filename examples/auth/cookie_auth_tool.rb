#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of using ADK::Auth with cookie-based authentication against httpbin.org
# This example demonstrates how to use cookies for authentication using the ADK tool framework.
#
# Usage:
#   ruby examples/auth/cookie_auth_tool.rb

require 'bundler/setup'
require 'adk'
require 'adk/auth'
require 'json'
require 'securerandom'

# Generate a fake session token for demonstration
COOKIE_VALUE = SecureRandom.hex(16)

puts "Cookie-Based Authentication Example"
puts "--------------------------------"
puts "Cookie Value: #{COOKIE_VALUE[0..5]}...#{COOKIE_VALUE[-4..-1]}"

# First, let's create a tool class for httpbin.org API
module ADK
  module Tools
    class HttpbinCookie < ADK::Tool
      include ADK::Tools::Base::HttpClient

      # Tool metadata
      tool_description 'Makes authenticated requests to httpbin.org using cookies'

      parameter :endpoint,
                type: :string,
                description: 'The httpbin endpoint to call (e.g., cookies, headers)',
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
        # Extract parameters
        endpoint = params[:endpoint]

        # Prepare request with authentication
        request = { 
          method: :get,
          path: "/#{endpoint}",
          headers: {}
        }

        # Apply authentication if configured
        if @auth_scheme && @auth_credential
          request = @auth_scheme.apply_to_request(request, @auth_credential)
        end

        # Make the request using HttpClient's helper with any auth headers
        response = http_get(
          request[:path], 
          headers: request[:headers]
        )

        # Parse and return the response
        begin
          data = JSON.parse(response.body)
          { status: :success, result: data }
        rescue JSON::ParserError => e
          raise ADK::ToolError, "Failed to parse API response: #{e.message}"
        end
      end
    end
  end
end

puts "\nDEMO: Using HttpbinCookie Tool with Cookie Authentication"
puts "---------------------------------------------------"

begin
  # Create session service for token storage
  session_service = ADK::SessionService::InMemory.new
  token_store = ADK::Auth::TokenStore.new(session_service)

  # Create an API Key scheme (we'll use this for cookie auth)
  scheme = ADK::Auth::Schemes::ApiKey.new

  # Create a credential with cookie configuration
  credential = ADK::Auth::Credential.new(
    auth_type: :api_key,
    api_key: COOKIE_VALUE,
    location: 'cookie',
    name: 'session_token'
  )

  # Create our HttpbinCookie tool instance with authentication
  cookie_tool = ADK::Tools::HttpbinCookie.new(
    auth_scheme: scheme,
    auth_credential: credential
  )

  # Example endpoints to test
  endpoints = ['cookies', 'headers']

  # Test each endpoint
  endpoints.each do |endpoint|
    puts "\nTesting endpoint: /#{endpoint}"
    
    begin
      result = cookie_tool.execute(
        endpoint: endpoint
      )

      if result[:status] == :success
        response_data = result[:result]
        
        case endpoint
        when 'cookies'
          puts "Cookies in request:"
          puts JSON.pretty_generate(response_data['cookies'])
        when 'headers'
          puts "Headers in request:"
          puts JSON.pretty_generate(response_data['headers'])
        end
      else
        puts "Error: #{result[:error_message]}"
      end
    rescue => e
      puts "Error testing #{endpoint}: #{e.message}"
      puts e.backtrace.join("\n") if ENV['DEBUG']
    end
  end

rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
end

puts "\nExample complete." 