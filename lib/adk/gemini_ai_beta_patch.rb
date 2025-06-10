# frozen_string_literal: true

# Monkey patch for gemini-ai gem to use v1beta API endpoint
# This allows us to use newer models that are only available in the beta API

require 'gemini-ai'

module Gemini
  module Controllers
    class Client
      # Store the original initialize method
      alias_method :original_initialize, :initialize

      def initialize(config)
        # Call the original initialize
        original_initialize(config)
        
        # Override the base_address to use v1beta if it's using the generative-language-api
        if @service == 'generative-language-api'
          # Force v1beta for the service version
          @service_version = 'v1beta'
          
          # Rebuild the base address with v1beta
          @base_address = "https://generativelanguage.googleapis.com/#{@service_version}"
          
          ADK.logger&.info("Gemini AI Client patched to use v1beta API endpoint") if defined?(ADK)
        end
      end
    end
  end
end

ADK.logger&.info("Gemini AI Beta patch loaded - API will use v1beta endpoint") if defined?(ADK) && ADK.respond_to?(:logger) 