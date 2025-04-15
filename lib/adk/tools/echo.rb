# File: lib/adk/tools/echo.rb
# frozen_string_literal: true

require 'faraday' # <-- Add require for Faraday
require 'json'    # <-- Add require for JSON parsing
require 'logger'  # <-- Add require for Logger

module ADK
  module Tools
    # Echo tool that echoes back a message along with a random cat fact.
    class Echo < Tool
      # Use a shared logger instance if possible, otherwise create a new one.
      # In a real app, logger might be passed in or configured globally.
      LOGGER = Logger.new($stdout)
      CAT_FACT_URL = 'https://catfact.ninja/fact'

      def initialize
        super(
          name: :echo,
          # Update the description
          description: 'Echoes back a message along with a random cat fact.',
          parameters: {
            message: {
              type: :string,
              description: 'The message to echo',
              required: true
            }
          }
        )
        # Initialize Faraday connection once
        @conn = Faraday.new(url: CAT_FACT_URL) do |faraday|
           faraday.adapter Faraday.default_adapter # Use the default adapter (e.g., net_http)
           faraday.response :raise_error           # Raise errors for 4xx/5xx responses
           faraday.request :url_encoded            # Form-encode POST params
           faraday.options.timeout = 5             # open/read timeout in seconds
           faraday.options.open_timeout = 2        # connection open timeout in seconds
         end

      end

      private

      # Updated execution method
      def perform_execution(params)
        original_message = params[:message]
        cat_fact = fetch_cat_fact

        # Combine the fact and the message
        "#{cat_fact}\n\nOriginal message: #{original_message}"
      end

      # Helper method to fetch the cat fact
      def fetch_cat_fact
        begin
          LOGGER.info("Fetching cat fact from #{CAT_FACT_URL}")
          response = @conn.get

          # Check if response body is valid JSON (Faraday doesn't parse automatically by default)
          # response.body will be a string here
          data = JSON.parse(response.body)

          # Extract the fact (assuming the API returns {"fact": "...", "length": ...})
          fact = data['fact']

          if fact && !fact.empty?
            LOGGER.info("Cat fact fetched successfully.")
            return "Cat Fact: #{fact}"
          else
            LOGGER.warn("Cat fact API response did not contain a 'fact' field or it was empty.")
            return "[Could not retrieve a valid cat fact.]"
          end

        rescue Faraday::Error => e
          # Covers connection errors, timeouts, 4xx/5xx responses due to :raise_error
          LOGGER.error("Error fetching cat fact (Faraday::Error): #{e.class} - #{e.message}")
          LOGGER.error("Response status: #{e.response[:status] if e.response}")
          LOGGER.error("Response body: #{e.response[:body] if e.response}")
          return "[Error connecting to cat fact API.]"
        rescue JSON::ParserError => e
          LOGGER.error("Error parsing cat fact JSON response: #{e.message}")
          return "[Error reading cat fact response.]"
        rescue StandardError => e
          LOGGER.error("Unexpected error fetching cat fact: #{e.class} - #{e.message}")
          LOGGER.error(e.backtrace.join("\n")) # Log backtrace for unexpected errors
          return "[Unexpected error retrieving cat fact.]"
        end
      end
    end
  end
end