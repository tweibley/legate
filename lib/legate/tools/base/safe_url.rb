# File: lib/legate/tools/base/safe_url.rb
# frozen_string_literal: true

require 'uri'
require 'ipaddr'
require_relative '../../auth/url_guard'
require_relative '../../errors'

module Legate
  module Tools
    module Base
      # SSRF guard for outbound tool requests.
      #
      # Validates a URL and returns the IP to pin the connection to (defeating
      # DNS-rebinding TOCTOU). It reuses the canonical {Legate::Auth::UrlGuard}
      # block-list so tools and the auth layer can never drift out of sync, and
      # raises a tool-appropriate {Legate::ToolArgumentError} on a bad target.
      #
      # Set LEGATE_ALLOW_PRIVATE_TOOL_URLS=1 to reach private/loopback hosts in
      # development (returns no pin so the request connects directly).
      module SafeUrl
        module_function

        # @param url [String] the target URL
        # @return [Array(URI, String|nil)] the parsed URI and the IP to pin to
        #   (nil when the dev bypass is active)
        # @raise [Legate::ToolArgumentError] if the URL is not http(s), cannot be
        #   resolved, or resolves to a restricted (loopback / private / link-local
        #   / CGNAT / 0.0.0.0-8) address
        def resolve!(url)
          uri = URI.parse(url.to_s)
          raise Legate::ToolArgumentError, "URL must use http or https: #{url}" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

          return [uri, nil] if ENV['LEGATE_ALLOW_PRIVATE_TOOL_URLS']

          ips = Legate::Auth::UrlGuard.resolved_ips(uri.host)
          raise Legate::ToolArgumentError, "Could not resolve host: #{uri.host}" if ips.empty?

          ips.each do |ip_str|
            ip = IPAddr.new(ip_str)
            next unless Legate::Auth::UrlGuard.restricted?(ip)

            raise Legate::ToolArgumentError,
                  "Blocked request to restricted network address (#{uri.host} -> #{ip_str})"
          rescue IPAddr::InvalidAddressError
            raise Legate::ToolArgumentError, "Invalid IP resolved for #{uri.host}: #{ip_str}"
          end

          [uri, ips.first]
        rescue URI::InvalidURIError => e
          raise Legate::ToolArgumentError.new("Invalid URL: #{url} - #{e.message}", cause: e)
        end
      end
    end
  end
end
