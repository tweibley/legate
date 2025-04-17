# File: lib/adk/tools/cat_facts.rb
# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative '../tool'

module ADK
  module Tools
    # Tool to fetch a random cat fact from an online API.
    class CatFacts < ADK::Tool
      # Define metadata for the tool, including name, description, and parameters.
      # This metadata is used by the Planner and potentially the UI.
      define_metadata(
        name: :cat_facts,
        description: 'Fetches a random cat fact from an online API.',
        parameters: {} # No parameters needed for a random fact
      )

      # The URL for the Cat Fact API.
      CAT_FACT_URL = 'https://catfact.ninja/fact'

      # Initializes the tool instance.
      # Sets up the Faraday HTTP connection.
      def initialize(**options)
        super(**options)
        # Initialize Faraday connection once with timeouts and error handling middleware
        @conn = Faraday.new(url: CAT_FACT_URL) do |faraday|
          faraday.adapter Faraday.default_adapter # Use the default HTTP adapter
          faraday.response :raise_error # Raise exceptions for HTTP 4xx/5xx responses
          faraday.request :url_encoded # Encode request params
          faraday.options.timeout = 5 # Set connection read timeout
          faraday.options.open_timeout = 2 # Set connection open timeout
        end
      rescue Faraday::Error => e # Catch potential errors during Faraday setup
        ADK.logger.error("CatFacts Tool: Failed to initialize Faraday connection: #{e.message}")
        @conn = nil # Ensure conn is nil if setup fails, preventing calls
      end

      private

      # The main execution method required by the ADK::Tool base class.
      # It delegates the actual work to the fetch_cat_fact helper method.
      # Accepts params hash but ignores it as this tool takes no parameters.
      #
      # @param _params [Hash] Ignored parameters.
      # @param _context [ADK::ToolContext, nil] The execution context (unused here).
      # @return [Hash] A standardized hash with :status and :result or :error_message.
      def perform_execution(_params, _context)
        fetch_cat_fact
      end

      # Helper method to perform the HTTP request and handle responses/errors.
      # Returns the standardized result hash.
      #
      # @return [Hash] A hash with :status (:success or :error) and :result/:error_message.
      def fetch_cat_fact
        # Check if the connection was successfully initialized
        unless @conn
          err_msg = "CatFacts Tool HTTP client not initialized"
          ADK.logger.error(err_msg)
          return { status: :error, error_message: err_msg }
        end

        # Perform the HTTP GET request and handle potential errors
        begin
          ADK.logger.info("Fetching cat fact from #{CAT_FACT_URL}")
          response = @conn.get # Perform the GET request

          # Parse the JSON response body
          data = JSON.parse(response.body)
          fact = data['fact'] # Extract the 'fact' field

          # Check if a valid fact was received
          if fact && !fact.empty?
            ADK.logger.info("Cat fact fetched successfully.")
            # Return success hash
            { status: :success, result: fact }
          else
            err_msg = "Cat fact API response did not contain a valid 'fact' field."
            ADK.logger.warn(err_msg)
            # Return error hash for invalid data
            { status: :error, error_message: err_msg }
          end

        # --- Specific Faraday/Network Error Handling (Ordered Most Specific to Least) ---
        rescue Faraday::TimeoutError => e
          err_msg = "Timeout connecting to cat fact API."
          ADK.logger.error("#{err_msg}: #{e.message}")
          { status: :error, error_message: err_msg }
        rescue Faraday::ConnectionFailed => e
          err_msg = "Connection failed for cat fact API."
          ADK.logger.error("#{err_msg}: #{e.message}")
          { status: :error, error_message: err_msg }
        rescue Faraday::Error => e # Catch other Faraday/HTTP errors (like 4xx/5xx)
          status_code = e.response[:status] if e.response
          err_msg = "Error fetching cat fact (HTTP Status: #{status_code || 'N/A'})."
          ADK.logger.error("#{err_msg} #{e.class}: #{e.message}")
          { status: :error, error_message: err_msg }
        # --- Other Potential Errors ---
        rescue JSON::ParserError => e
          err_msg = "Error reading cat fact response (JSON parse failed)."
          ADK.logger.error("#{err_msg}: #{e.message}")
          { status: :error, error_message: err_msg }
        rescue StandardError => e # Catch any other unexpected errors
          err_msg = "Unexpected error retrieving cat fact."
          ADK.logger.error("#{err_msg}: #{e.class} - #{e.message}")
          ADK.logger.error(e.backtrace.first(5).join("\n")) # Log stack trace for debugging
          { status: :error, error_message: err_msg }
        end
      end # end fetch_cat_fact
    end # End CatFacts class
  end # End Tools module
end # End ADK module
