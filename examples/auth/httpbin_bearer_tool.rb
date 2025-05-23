#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'adk'
require 'adk/auth'
require 'adk/auth/schemes/http_bearer'
require 'json'

# Example of using ADK::Auth with bearer token authentication against httpbin.org
# This example demonstrates how to use bearer tokens for authentication using the ADK tool framework.

module ADK
  module Tools
    class HttpbinBearer < ADK::Tool
      include ADK::Tools::Base::HttpClient

      # Tool metadata
      tool_description 'Makes authenticated requests to httpbin.org using bearer token'

      parameter :endpoint,
                type: :string,
                description: 'The httpbin endpoint to call (e.g., bearer, headers)',
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
          headers: {
            'Accept' => 'application/json'
          }
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
          case response.status
          when 200
            {
              status: :success,
              message: 'Successfully authenticated with bearer token',
              result: data
            }
          when 401
            {
              status: :error,
              message: 'Authentication failed. Invalid or missing bearer token.',
              error: data['message'] || 'Unauthorized'
            }
          else
            {
              status: :error,
              message: "Request failed with status #{response.status}",
              error: data
            }
          end
        rescue JSON::ParserError => e
          raise ADK::ToolError, "Failed to parse API response: #{e.message}"
        end
      end
    end
  end
end

if $0 == __FILE__
  puts "Bearer Token Authentication Example"
  puts "--------------------------------"

  begin
    # Create session service for token storage
    session_service = ADK::SessionService::InMemory.new
    token_store = ADK::Auth::TokenStore.new(session_service)

    # Create a bearer token scheme
    scheme = ADK::Auth::Schemes::HTTPBearer.new

    # Create a credential with the bearer token
    # In a real application, you would get this from an environment variable
    credential = ADK::Auth::Credential.new(
      auth_type: :http_bearer,
      bearer_token: 'test-bearer-token'
    )

    # Create our HttpbinBearer tool instance with authentication
    bearer_tool = ADK::Tools::HttpbinBearer.new(
      auth_scheme: scheme,
      auth_credential: credential
    )

    # Example endpoints to test
    endpoints = ['bearer', 'headers']

    # Test each endpoint
    endpoints.each do |endpoint|
      puts "\nTesting endpoint: /#{endpoint}"

      begin
        result = bearer_tool.execute(
          endpoint: endpoint
        )

        if result[:status] == :success
          response_data = result[:result]
          puts "Success: #{result[:message]}"

          case endpoint
          when 'bearer'
            puts "Bearer auth response:"
            puts JSON.pretty_generate(response_data)
          when 'headers'
            puts "Headers in request:"
            puts JSON.pretty_generate(response_data['headers'])
          end
        else
          puts "Error: #{result[:message]}"
          puts "Details: #{result[:error]}"
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
end
