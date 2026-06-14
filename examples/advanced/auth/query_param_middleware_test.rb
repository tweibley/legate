#!/usr/bin/env ruby
# frozen_string_literal: true

# Test focusing on query parameter handling in middleware
#
# Usage:
#   ruby examples/advanced/auth/query_param_middleware_test.rb

require 'bundler/setup'
require 'json'
require 'excon'
require 'uri'

# Middleware that correctly adds a query parameter
class QueryParamMiddleware < Excon::Middleware::Base
  def initialize(stack)
    puts 'QueryParamMiddleware initialized'
    @stack = stack
    @api_key = 'test-api-key-123'
    @api_key_name = 'apikey'
    super(stack)
  end

  def request_call(datum)
    puts 'QueryParamMiddleware request_call invoked'
    puts "  Method: #{datum[:method]}, Path: #{datum[:path]}"
    puts "  Original query: #{datum[:query].inspect}"
    puts "  Connect timeout: #{datum[:connect_timeout]}"
    puts "  Read timeout: #{datum[:read_timeout]}"
    puts "  Write timeout: #{datum[:write_timeout]}"

    # Add API key to query parameters
    query = datum[:query] || {}

    # Convert query to Hash if it's a string
    if query.is_a?(String)
      params = {}
      URI.decode_www_form(query).each do |key, value|
        params[key] = value
      end
      query = params
    end

    # Add API key parameter
    query[@api_key_name] = @api_key

    # Update the datum with the modified query
    datum[:query] = query

    # Debug the updated query
    puts "  Modified query: #{datum[:query].inspect}"

    # Continue with the middleware stack - pass through the modified datum
    @stack.request_call(datum)
  end

  def response_call(datum)
    puts 'QueryParamMiddleware response_call invoked'
    # Pass the datum through unmodified
    @stack.response_call(datum)
  end
end

puts 'Query Parameter Middleware Test'
puts '----------------------------'

puts "\nTest 1: Direct API call with Excon"
puts '-------------------------------'

begin
  # Make a direct Excon request
  url = 'https://httpbin.org/get?test=value'

  puts "Making direct request to: #{url}"

  # Create the connection with normal timeouts
  response = Excon.get(url,
                       connect_timeout: 10,
                       read_timeout: 10,
                       write_timeout: 10)

  puts "Response Status: #{response.status}"

  if response.status == 200
    data = JSON.parse(response.body)
    puts "Data received: #{data['args'].inspect}"
  else
    puts "Error: #{response.status} - #{response.body}"
  end
rescue StandardError => e
  puts "Request Error: #{e.message}"
  puts e.backtrace.join("\n")
end

puts "\nTest 2: Query Parameter Middleware"
puts '-------------------------------'

begin
  # Create a connection with our custom middleware
  connection = Excon.new('https://httpbin.org',
                         middlewares: [
                           Excon::Middleware::ResponseParser,
                           Excon::Middleware::Expects,
                           Excon::Middleware::Idempotent,
                           Excon::Middleware::Instrumentor,
                           Excon::Middleware::Mock,
                           QueryParamMiddleware # Our query parameter middleware
                         ],
                         connect_timeout: 10,
                         read_timeout: 10,
                         write_timeout: 10)

  puts 'Connection created with query parameter middleware'
  puts 'Making request...'

  # Make the request
  response = connection.request(
    method: :get,
    path: '/get',
    query: {
      test: 'value'
    }
  )

  puts "Response Status: #{response.status}"

  if response.status == 200
    data = JSON.parse(response.body)
    puts "Data received: #{data['args'].inspect}"
  else
    puts "Error: #{response.status} - #{response.body}"
  end
rescue StandardError => e
  puts "Request Error: #{e.message}"
  puts e.backtrace.join("\n")
end

puts "\nTest complete."
