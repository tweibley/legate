#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of using ADK::Auth with OpenWeatherMap API using the tool-based approach
# and proper authentication handling through HttpClient.
#
# Usage:
#   ruby examples/auth/openweather_tool.rb

require 'bundler/setup'
require 'adk'
require 'adk/auth'
require 'json'
# API Key for OpenWeatherMap
OPENWEATHER_API_KEY = ENV['API_KEY']

puts "OpenWeatherMap API Tool-Based Authentication Example"
puts "------------------------------------------------"
puts "API Key: #{OPENWEATHER_API_KEY[0..5]}...#{OPENWEATHER_API_KEY[-4..-1]}"

# First, let's create a tool class for OpenWeather API
module ADK
  module Tools
    class OpenWeather < ADK::Tool
      include ADK::Tools::Base::HttpClient

      # Tool metadata
      tool_description 'Fetches weather data from OpenWeatherMap API'

      parameter :city,
                type: :string,
                description: 'The city to get weather for',
                required: true

      parameter :country_code,
                type: :string,
                description: 'The country code (e.g., uk, us, jp)',
                required: true

      parameter :units,
                type: :string,
                description: 'The units to use (metric or imperial)',
                required: false

      def initialize(options = {})
        super()
        @auth_scheme = options[:auth_scheme]
        @auth_credential = options[:auth_credential]
        setup_http_client(
          base_url: 'https://api.openweathermap.org',
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
        city = params[:city]
        country_code = params[:country_code]
        units = params.fetch(:units, 'metric')

        # Prepare query parameters
        query = {
          q: "#{city},#{country_code}",
          units: units
        }

        # If we have auth credentials, let them be applied through the auth scheme
        if @auth_scheme && @auth_credential
          request = { query: query }
          modified_request = @auth_scheme.apply_to_request(request, @auth_credential)
          query = modified_request[:query]
        end

        # Make the request using HttpClient's helper
        response = http_get('/data/2.5/weather', query: query)

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

puts "\nDEMO 1: Using OpenWeather Tool with API Key Authentication"
puts "-----------------------------------------------------"

begin
  # Create an API Key scheme
  scheme = ADK::Auth::Schemes::ApiKey.new

  # Create a credential with the API key
  credential = ADK::Auth::Credential.new(
    auth_type: :api_key,
    api_key: OPENWEATHER_API_KEY,
    location: 'query',
    name: 'appid'
  )

  # Create our OpenWeather tool instance with authentication
  weather_tool = ADK::Tools::OpenWeather.new(
    auth_scheme: scheme,
    auth_credential: credential
  )

  # Example cities to check weather for
  cities = [
    { city: 'London', country: 'uk' },
    { city: 'Tokyo', country: 'jp' },
    { city: 'New York', country: 'us' }
  ]

  # Get weather for each city
  cities.each do |location|
    puts "\nChecking weather for #{location[:city]}, #{location[:country].upcase}..."
    
    begin
      result = weather_tool.execute(
        city: location[:city],
        country_code: location[:country]
      )

      if result[:status] == :success
        weather_data = result[:result]
        puts "Location: #{weather_data['name']}, #{weather_data['sys']['country']}"
        puts "Weather: #{weather_data['weather'][0]['main']} - #{weather_data['weather'][0]['description']}"
        puts "Temperature: #{weather_data['main']['temp']}°C (Feels like: #{weather_data['main']['feels_like']}°C)"
        puts "Humidity: #{weather_data['main']['humidity']}%"
        puts "Wind: #{weather_data['wind']['speed']} m/s"
      else
        puts "Error: #{result[:error_message]}"
      end
    rescue => e
      puts "Error getting weather for #{location[:city]}: #{e.message}"
      puts e.backtrace.join("\n") if ENV['DEBUG']
    end
  end

rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
end

puts "\nExample complete." 