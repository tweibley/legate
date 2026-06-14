# frozen_string_literal: true

# Monkey patch for the gemini-ai gem to use the v1beta API endpoint, which
# exposes newer models. It reaches into gemini-ai's private @service /
# @service_version / @base_address ivars, so it is written defensively: if a
# future gemini-ai release renames those internals, the patch degrades to a
# logged warning instead of crashing planning at require time. gemini-ai is
# pinned (~> 4.2.0) to keep this stable.

require 'gemini-ai'

if defined?(Gemini::Controllers::Client)
  module Gemini
    module Controllers
      class Client
        # Store the original initialize method
        alias original_initialize initialize

        def initialize(config)
          original_initialize(config)

          # Force v1beta when talking to the generative-language API. Guard the
          # ivar pokes so a gemini-ai internals change can't break construction.
          return unless instance_variable_defined?(:@service) && @service == 'generative-language-api'

          @service_version = 'v1beta'
          @base_address = "https://generativelanguage.googleapis.com/#{@service_version}"
          Legate.logger&.debug('Gemini AI Client patched to use v1beta API endpoint') if defined?(Legate)
        rescue StandardError => e
          Legate.logger&.warn("Gemini v1beta patch could not apply (gemini-ai internals may have changed): #{e.message}") if defined?(Legate)
        end
      end
    end
  end

  Legate.logger&.debug('Gemini AI Beta patch loaded - API will use v1beta endpoint') if defined?(Legate) && Legate.respond_to?(:logger)
elsif defined?(Legate)
  Legate.logger&.warn('Gemini::Controllers::Client not found; skipping v1beta patch (gemini-ai may have changed).')
end
