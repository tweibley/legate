# File: lib/adk/tools/cat_facts.rb
# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative '../tool' # Ensure base class is loaded

module ADK
  module Tools
    # Tool to fetch a random cat fact.
    class CatFacts < Tool
      # --- Define Metadata (This triggers registration) ---
      define_metadata(
        name: :cat_facts,
        description: 'Fetches a random cat fact from an online API.',
        parameters: {} # No parameters needed for a random fact
      )
      # --- End Metadata ---

      CAT_FACT_URL = 'https://catfact.ninja/fact'

      def initialize(**options)
        super(**options)
        # Initialize Faraday connection once
        @conn = Faraday.new(url: CAT_FACT_URL) do |faraday|
          faraday.adapter Faraday.default_adapter
          faraday.response :raise_error # Raise errors for 4xx/5xx responses
          faraday.request :url_encoded
          faraday.options.timeout = 5
          faraday.options.open_timeout = 2
        end
      rescue Faraday::Error => e # Catch potential setup errors
        ADK.logger.error("CatFacts Tool: Failed to initialize Faraday connection: #{e.message}")
        @conn = nil # Ensure conn is nil if setup fails
      end

      private

      # perform_execution calls the helper method
      def perform_execution(_params) # Takes params but ignores them
        fetch_cat_fact
      end

      # Helper method to fetch the cat fact (Moved from Echo)
      def fetch_cat_fact
        unless @conn
          return "[CatFacts Tool HTTP client not initialized]"
        end

        begin
          ADK.logger.info("Fetching cat fact from #{CAT_FACT_URL}")
          response = @conn.get
          data = JSON.parse(response.body)
          fact = data['fact']

          if fact && !fact.empty?
            ADK.logger.info("Cat fact fetched successfully.")
            return fact # Return just the fact string
          else
            ADK.logger.warn("Cat fact API response did not contain a 'fact' field or it was empty.")
            return "[Could not retrieve a valid cat fact.]"
          end
        rescue Faraday::Error => e
          ADK.logger.error("Error fetching cat fact (Faraday::Error): #{e.class} - #{e.message}")
          ADK.logger.error("Response status: #{e.response[:status] if e.response}")
          return "[Error connecting to cat fact API.]"
        rescue JSON::ParserError => e
          ADK.logger.error("Error parsing cat fact JSON response: #{e.message}")
          return "[Error reading cat fact response.]"
        rescue StandardError => e
          ADK.logger.error("Unexpected error fetching cat fact: #{e.class} - #{e.message}")
          ADK.logger.error(e.backtrace.join("\n"))
          return "[Unexpected error retrieving cat fact.]"
        end
      end
    end # End CatFacts class
  end # End Tools module
end # End ADK module
