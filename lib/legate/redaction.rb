# File: lib/legate/redaction.rb
# frozen_string_literal: true

module Legate
  # Strips secrets out of strings before they're logged or surfaced to users.
  #
  # LLM/HTTP client errors routinely embed the request URL — which for Gemini
  # carries the API key as a `?key=...` query parameter — so error messages and
  # logs must be scrubbed before they leave the process.
  module Redaction
    module_function

    REPLACEMENT = '[REDACTED]'

    # `key=`, `api_key=`, `access_token=`, `token=` query/form parameters.
    SECRET_PARAM = /([?&](?:key|api[_-]?key|access_token|token)=)[^&\s"']+/i
    # `Authorization: Bearer <token>`.
    BEARER = %r{(Bearer\s+)[A-Za-z0-9\-._~+/]+=*}i
    # Google API keys by their `AIza` prefix — a belt-and-suspenders catch even
    # if the key shows up somewhere the patterns above don't match.
    GOOGLE_KEY = /AIza[0-9A-Za-z\-_]{10,}/

    # @param text [Object] anything stringifiable
    # @return [String] the text with known secret shapes replaced
    def redact(text)
      text.to_s
          .gsub(SECRET_PARAM, "\\1#{REPLACEMENT}")
          .gsub(BEARER, "\\1#{REPLACEMENT}")
          .gsub(GOOGLE_KEY, REPLACEMENT)
    end
  end
end
