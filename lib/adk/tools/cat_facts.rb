# File: lib/adk/tools/cat_facts.rb
# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative '../tool'

module ADK
  module Tools
    class CatFacts < Tool
      define_metadata(
        name: :cat_facts,
        description: 'Fetches a random cat fact from an online API.',
        parameters: {}
      )

      CAT_FACT_URL = 'https://catfact.ninja/fact'

      def initialize(**options)
        super(**options)
        @conn = Faraday.new(url: CAT_FACT_URL) do |faraday|
          # ... (faraday setup remains the same) ...
          faraday.adapter Faraday.default_adapter
          faraday.response :raise_error # Raise errors for 4xx/5xx responses
          faraday.request :url_encoded
          faraday.options.timeout = 5
          faraday.options.open_timeout = 2
        end
      rescue Faraday::Error => e
        ADK.logger.error("CatFacts Tool: Failed to initialize Faraday connection: #{e.message}")
        @conn = nil
      end

      private

      # perform_execution calls the helper method and returns its hash
      def perform_execution(_params)
        fetch_cat_fact
      end

      # Helper method modified to return the standard hash format
      def fetch_cat_fact
        unless @conn
          err_msg = "CatFacts Tool HTTP client not initialized"
          ADK.logger.error(err_msg)
          return { status: :error, error_message: err_msg }
        end

        begin
          ADK.logger.info("Fetching cat fact from #{CAT_FACT_URL}")
          response = @conn.get
          data = JSON.parse(response.body)
          fact = data['fact']

          if fact && !fact.empty?
            ADK.logger.info("Cat fact fetched successfully.")
            # --- Return Success Hash ---
            { status: :success, result: fact }
          else
            err_msg = "Cat fact API response did not contain a valid 'fact' field."
            ADK.logger.warn(err_msg)
            # --- Return Error Hash ---
            { status: :error, error_message: err_msg }
          end
        rescue Faraday::TimeoutError => e
          err_msg = "Timeout connecting to cat fact API."
          ADK.logger.error("#{err_msg}: #{e.message}")
          { status: :error, error_message: err_msg }
        rescue Faraday::ConnectionFailed => e
          err_msg = "Connection failed for cat fact API."
          ADK.logger.error("#{err_msg}: #{e.message}")
          { status: :error, error_message: err_msg }
        rescue Faraday::Error => e # Catch other Faraday/HTTP errors (like 4xx/5xx)
          err_msg = "Error fetching cat fact (HTTP Status: #{e.response[:status] if e.response})."
          ADK.logger.error("#{err_msg} #{e.class}: #{e.message}")
          { status: :error, error_message: err_msg }
        rescue JSON::ParserError => e
          err_msg = "Error reading cat fact response (JSON parse failed)."
          ADK.logger.error("#{err_msg}: #{e.message}")
          { status: :error, error_message: err_msg }
        rescue StandardError => e
          err_msg = "Unexpected error retrieving cat fact."
          ADK.logger.error("#{err_msg}: #{e.class} - #{e.message}")
          ADK.logger.error(e.backtrace.first(5).join("\n"))
          { status: :error, error_message: err_msg }
        end
      end
    end # End CatFacts class
  end # End Tools module
end # End ADK module
