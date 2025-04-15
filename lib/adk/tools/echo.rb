# File: lib/adk/tools/echo.rb
# frozen_string_literal: true

require 'faraday'
require 'json'
require 'logger'
require_relative '../tool' # Ensure base class is loaded

module ADK
  module Tools
    # Echo tool that echoes back a message along with a random cat fact.
    class Echo < Tool
      # --- Define Metadata ---
      define_metadata(
        name: :echo,
        description: 'Echoes back a message along with a random cat fact.',
        parameters: {
          message: {
            type: :string,
            description: 'The message to echo',
            required: true
          }
        }
      )
      # --- End Metadata ---

      LOGGER = Logger.new($stdout)
      CAT_FACT_URL = 'https://catfact.ninja/fact'

      def initialize(**options)
        # Call the modified base class initializer which sets vars from class metadata
        super(**options)

        # Initialize Faraday connection once
        @conn = Faraday.new(url: CAT_FACT_URL) do |faraday|
          faraday.adapter Faraday.default_adapter
          faraday.response :raise_error
          faraday.request :url_encoded
          faraday.options.timeout = 5
          faraday.options.open_timeout = 2
        end
      end

      private

      # Updated execution method to handle string or symbol keys
      def perform_execution(params)
        # Use fetch with string key as primary, fallback to symbol key
        original_message = params.fetch('message') { params.fetch(:message, nil) }

        # Handle case where message might be missing despite validation ( belt-and-suspenders)
        unless original_message
          raise ArgumentError, "Internal Error: Message parameter missing in perform_execution for Echo tool."
        end

        cat_fact = fetch_cat_fact
        "#{cat_fact}\n\nOriginal message: #{original_message}"
      end

      # Helper method to fetch the cat fact (remains the same)
      def fetch_cat_fact
        # ... (existing fetch_cat_fact logic) ...
        begin
          LOGGER.info("Fetching cat fact from #{CAT_FACT_URL}")
          response = @conn.get
          data = JSON.parse(response.body)
          fact = data['fact']
          if fact && !fact.empty?
            LOGGER.info("Cat fact fetched successfully.")
            return "Cat Fact: #{fact}"
          else
            LOGGER.warn("Cat fact API response did not contain a 'fact' field or it was empty.")
            return "[Could not retrieve a valid cat fact.]"
          end
        rescue Faraday::Error => e
          LOGGER.error("Error fetching cat fact (Faraday::Error): #{e.class} - #{e.message}")
          # ... other logging ...
          return "[Error connecting to cat fact API.]"
        rescue JSON::ParserError => e
          LOGGER.error("Error parsing cat fact JSON response: #{e.message}")
          return "[Error reading cat fact response.]"
        rescue StandardError => e
          LOGGER.error("Unexpected error fetching cat fact: #{e.class} - #{e.message}")
          LOGGER.error(e.backtrace.join("\n"))
          return "[Unexpected error retrieving cat fact.]"
        end
      end
    end # End Echo class

    # Trigger registration explicitly after class definition (if needed, base initialize does it now)
    # Echo.register_tool_class # This line might not be needed if initialize handles it
  end # End Tools module
end # End ADK module
