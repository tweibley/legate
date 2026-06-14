#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of using Legate::Auth with OpenWeatherMap API
#
# This example demonstrates different ways to authenticate with OpenWeatherMap API
# using both direct Excon calls and Legate::Auth middleware.
#
# Usage:
#   ruby examples/advanced/auth/openweather_api.rb

require 'bundler/setup'
require 'legate'
require 'legate/auth' # Explicitly require the auth module
require 'json'
require 'excon'
require 'legate/session_service/in_memory'
require 'uri'

# Enable debug mode
ENV['DEBUG'] = 'true'

# API Key for OpenWeatherMap
OPENWEATHER_API_KEY = ENV['API_KEY']

puts 'OpenWeatherMap API Authentication Example'
puts '----------------------------------------'
puts "API Key: #{OPENWEATHER_API_KEY[0..5]}...#{OPENWEATHER_API_KEY[-4..-1]}"

# Create session service for token storage
session_service = Legate::SessionService::InMemory.new

# Create a basic token store for caching
token_store = Legate::Auth::TokenStore.new(session_service)

# Create the ApiKey scheme for our OpenWeatherMap API
api_key_scheme = Legate::Auth::Schemes::ApiKey.new

# Create the credential to use with the scheme
api_key_credential = Legate::Auth::Credential.new(
  auth_type: :api_key,
  api_key: OPENWEATHER_API_KEY,
  location: 'query',
  name: 'appid'
)

puts "\nDEMO 1: Direct API call with Excon (no Legate middleware)"
puts '------------------------------------------------------'

begin
  # Make a direct Excon request to the OpenWeatherMap API
  url = 'https://api.openweathermap.org/data/2.5/weather?q=London,uk&units=metric'

  # Manually add the API key to the URL
  url_with_key = "#{url}&appid=#{OPENWEATHER_API_KEY}"

  puts "Making request to: #{url_with_key.gsub(OPENWEATHER_API_KEY, 'API_KEY_REDACTED')}"

  response = Excon.get(url_with_key,
                       connect_timeout: 30,
                       read_timeout: 30,
                       write_timeout: 30)

  puts "Response Status: #{response.status}"

  if response.status == 200
    weather_data = JSON.parse(response.body)
    puts "Location: #{weather_data['name']}, #{weather_data['sys']['country']}"
    puts "Weather: #{weather_data['weather'][0]['main']} - #{weather_data['weather'][0]['description']}"
    puts "Temperature: #{weather_data['main']['temp']}°C (Feels like: #{weather_data['main']['feels_like']}°C)"
    puts "Humidity: #{weather_data['main']['humidity']}%"
    puts "Wind: #{weather_data['wind']['speed']} m/s"
  else
    puts "Error: #{response.status} - #{response.body}"
  end
rescue StandardError => e
  puts "Request Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
end

puts "\nDEMO 2: Using Legate::Auth to apply authentication manually"
puts '------------------------------------------------------'

begin
  # Create a request hash (without authentication)
  request = {
    method: :get,
    path: '/data/2.5/weather',
    query: {
      q: 'Paris,fr',
      units: 'metric'
    },
    headers: {}
  }

  # Use Legate::Auth::ToolIntegration to apply authentication to the request
  puts "Applying authentication with params: #{request.inspect}"
  request_with_auth = Legate::Auth::ToolIntegration.apply_authentication(
    request,
    api_key_scheme,
    api_key_credential,
    token_store
  )

  puts "Authentication applied: #{request_with_auth.inspect}"

  # Extract the query parameters - we need to handle this manually
  query_params = request_with_auth[:query]

  # Add appid parameter manually if it's not already present
  query_hash = if query_params.is_a?(Hash)
                 # If it's already a hash, we can use it directly
                 query_params
               elsif query_params.is_a?(String)
                 # Parse the query string into a hash
                 params = {}
                 URI.decode_www_form(query_params).each do |key, value|
                   params[key] = value
                 end
                 params
               else
                 # Default to an empty hash if we can't parse it
                 { q: 'Paris,fr', units: 'metric' }
               end

  # Make sure the API key is in the query parameters
  query_hash['appid'] ||= OPENWEATHER_API_KEY

  # Construct the full URL from the request with proper query params
  base_url = 'https://api.openweathermap.org'
  path = request_with_auth[:path]

  # Convert the hash to a query string
  query_string = URI.encode_www_form(query_hash)

  # Full URL
  full_url = "#{base_url}#{path}?#{query_string}"
  puts "Request URL with auth applied: #{full_url.gsub(OPENWEATHER_API_KEY, 'API_KEY_REDACTED')}"

  # Make the request
  response = Excon.get(full_url,
                       connect_timeout: 30,
                       read_timeout: 30,
                       write_timeout: 30)

  puts "Response Status: #{response.status}"

  if response.status == 200
    weather_data = JSON.parse(response.body)
    puts "Location: #{weather_data['name']}, #{weather_data['sys']['country']}"
    puts "Weather: #{weather_data['weather'][0]['main']} - #{weather_data['weather'][0]['description']}"
    puts "Temperature: #{weather_data['main']['temp']}°C (Feels like: #{weather_data['main']['feels_like']}°C)"
    puts "Humidity: #{weather_data['main']['humidity']}%"
    puts "Wind: #{weather_data['wind']['speed']} m/s"
  else
    puts "Error: #{response.status} - #{response.body}"
  end
rescue StandardError => e
  puts "Request Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
end

puts "\nDEMO 3: Using API Key directly with Excon"
puts '-------------------------------------'

begin
  # Create a request with direct query params approach
  puts 'Making direct query parameter request...'

  # Use a direct approach without middleware
  query_params = {
    q: 'Tokyo,jp',
    units: 'metric',
    appid: OPENWEATHER_API_KEY
  }

  # Create the connection
  connection = Excon.new('https://api.openweathermap.org',
                         connect_timeout: 10,
                         read_timeout: 10,
                         write_timeout: 10)

  # Make the request directly
  response = connection.request(
    method: :get,
    path: '/data/2.5/weather',
    query: query_params
  )

  puts "Response Status: #{response.status}"

  if response.status == 200
    weather_data = JSON.parse(response.body)
    puts "Location: #{weather_data['name']}, #{weather_data['sys']['country']}"
    puts "Weather: #{weather_data['weather'][0]['main']} - #{weather_data['weather'][0]['description']}"
    puts "Temperature: #{weather_data['main']['temp']}°C (Feels like: #{weather_data['main']['feels_like']}°C)"
    puts "Humidity: #{weather_data['main']['humidity']}%"
    puts "Wind: #{weather_data['wind']['speed']} m/s"
  else
    puts "Error: #{response.status} - #{response.body}"
  end
rescue StandardError => e
  puts "Request Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
end

puts "\nDEMO 4: Using Legate::Auth middleware (with fixed implementation)"
puts '---------------------------------------------------------'

begin
  puts 'Creating connection with Legate::Auth middleware...'

  # Use the fixed middleware via Legate::Auth.create_api_key_connection
  connection = Legate::Auth.create_api_key_connection(
    'https://api.openweathermap.org',
    api_key: OPENWEATHER_API_KEY,
    location: 'query',
    name: 'appid',
    token_store: token_store
  )

  puts 'Connection created. Making request to get weather for New York...'

  # Make the request through the middleware
  response = connection.request(
    method: :get,
    path: '/data/2.5/weather',
    query: {
      q: 'New York,us',
      units: 'metric'
    }
  )

  puts "Response Status: #{response.status}"

  if response.status == 200
    weather_data = JSON.parse(response.body)
    puts "Location: #{weather_data['name']}, #{weather_data['sys']['country']}"
    puts "Weather: #{weather_data['weather'][0]['main']} - #{weather_data['weather'][0]['description']}"
    puts "Temperature: #{weather_data['main']['temp']}°C (Feels like: #{weather_data['main']['feels_like']}°C)"
    puts "Humidity: #{weather_data['main']['humidity']}%"
    puts "Wind: #{weather_data['wind']['speed']} m/s"
  else
    puts "Error: #{response.status} - #{response.body}"
  end
rescue StandardError => e
  puts "Request Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
end

puts "\nExample complete."
