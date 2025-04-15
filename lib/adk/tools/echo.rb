# File: lib/adk/tools/echo.rb
# frozen_string_literal: true

# Removed requires for faraday, json, logger
require_relative '../tool' # Ensure base class is loaded

module ADK
  module Tools
    # Echo tool that simply echoes back a message.
    class Echo < Tool
      # --- Define Metadata ---
      define_metadata(
        name: :echo,
        description: 'Echoes back the provided message.', # Updated description
        parameters: {
          message: {
            type: :string,
            description: 'The message to echo',
            required: true
          }
        }
      )
      # --- End Metadata ---

      # REMOVED: LOGGER constant
      # REMOVED: CAT_FACT_URL constant

      def initialize(**options)
        super(**options)
        # REMOVED: Faraday connection setup
      end

      private

      # Simplified perform_execution
      def perform_execution(params)
        # Use fetch for safety, ensure it handles string/symbol keys if necessary,
        # though validation should pass string keys now.
        message = params.fetch('message') { params.fetch(:message, nil) }

        unless message
          # This shouldn't happen if validation passes, but good practice
          raise ArgumentError, "Internal Error: Message parameter missing in perform_execution for Echo tool."
        end

        message # Just return the message
      end

      # REMOVED: fetch_cat_fact method
    end # End Echo class
  end # End Tools module
end # End ADK module
