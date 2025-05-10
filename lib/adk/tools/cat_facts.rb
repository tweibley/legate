# File: lib/adk/tools/cat_facts.rb
# frozen_string_literal: true

# Removed Faraday and JSON requires, handled by HttpClient
require_relative '../tool'
require_relative 'base/http_client' # Include the base module

module ADK
  module Tools
    # Tool to fetch a random cat fact from an online API.
    class CatFacts < ADK::Tool
      include ADK::Tools::Base::HttpClient # Include the mixin

      # --- New DSL Metadata ---
      # Name :cat_facts will be inferred
      tool_description 'Fetches a random cat fact from an online API.'
      # No parameters needed, so no `parameter` calls.
      # --- End New DSL Metadata ---

      # The base URL for the Cat Fact API.
      CAT_FACT_BASE_URL = 'https://catfact.ninja'

      # Initializes the tool instance.
      # Sets up the HTTP client using the base module.
      def initialize(**options)
        super(**options)
        # Use the base module to set up the client
        # It handles initialization errors and logging internally.
        setup_http_client(base_url: CAT_FACT_BASE_URL)
      end

      private

      # The main execution method required by the ADK::Tool base class.
      # It delegates the actual work to the fetch_cat_fact helper method.
      def perform_execution(_params, _context)
        fetch_cat_fact
      end

      # Helper method to perform the HTTP request using the HttpClient module
      # and handle responses/errors.
      # Returns the standardized result hash.
      #
      # @return [Hash] A hash with :status (:success or :error) and :result/:error_message.
      # @raise [ADK::ToolError] Propagates errors from http_get, parse_json_response, or validation.
      def fetch_cat_fact
        ADK.logger.info('Fetching cat fact using HttpClient...')

        # Perform the GET request using the base module helper
        # Network/HTTP/Timeout errors are automatically handled and raised as ADK::ToolError
        response = http_get('/fact')

        # Parse the JSON response body directly
        begin
          data = JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise ADK::ToolError, "Failed to parse JSON response from Cat Fact API: #{e.message}", cause: e
        end

        fact = data['fact'] # Extract the 'fact' field

        # Check if a valid fact was received
        if fact && !fact.empty?
          ADK.logger.info('Cat fact fetched successfully.')
          { status: :success, result: fact }
        else
          # Raise an error if the expected field is missing or empty
          err_msg = "Cat fact API response did not contain a valid 'fact' field."
          ADK.logger.warn(err_msg)
          raise ADK::ToolError, err_msg
        end

        # No need for extensive rescue blocks here anymore.
        # ADK::ToolError from http_get, parse_json_response, or the validation
        # will propagate up and be handled by the ADK runtime.
        # StandardError might still occur in unexpected places, but the base
        # HttpClient tries to catch most common issues.
      end # end fetch_cat_fact
    end # End CatFacts class
  end # End Tools module
end # End ADK module
