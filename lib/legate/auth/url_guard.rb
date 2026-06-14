# File: lib/legate/auth/url_guard.rb
# frozen_string_literal: true

require 'resolv'
require 'ipaddr'
require 'uri'
require_relative 'error'

module Legate
  module Auth
    # Canonical SSRF guard for outbound auth and credential-test URLs.
    #
    # Resolves the host and refuses loopback, link-local, private,
    # 0.0.0.0/8 and CGNAT (100.64.0.0/10) targets so a misconfigured or
    # attacker-supplied URL cannot reach internal services or cloud metadata.
    # Set LEGATE_ALLOW_PRIVATE_AUTH_URLS=1 to bypass in development.
    module UrlGuard
      BLOCKED_RANGES = [
        IPAddr.new('0.0.0.0/8'),
        IPAddr.new('100.64.0.0/10')
      ].freeze

      module_function

      # @param url [String] The URL to validate
      # @param label [String] A label used in error messages
      # @raise [Legate::Auth::Error] If the URL resolves to a restricted address
      def validate!(url, label: 'Auth URL')
        return if ENV['LEGATE_ALLOW_PRIVATE_AUTH_URLS']

        hostname = parse_http_uri!(url, label).host
        ips = resolved_ips(hostname)
        # Fail closed: if we can't resolve the host, refuse rather than letting
        # the request through (an unresolvable host can't be checked, and a
        # resolver discrepancy could otherwise be used to slip past the guard).
        if ips.empty?
          raise Legate::Auth::Error,
                "#{label}: could not resolve host '#{hostname}' for SSRF validation."
        end

        ips.each do |ip_str|
          ip = IPAddr.new(ip_str)
          next unless restricted?(ip)

          raise Legate::Auth::Error,
                "#{label} resolves to restricted network address (#{hostname} -> #{ip_str}). " \
                'Set LEGATE_ALLOW_PRIVATE_AUTH_URLS=1 for development.'
        rescue IPAddr::InvalidAddressError
          next # skip unparseable IPs from the resolver
        end
      end

      # @raise [Legate::Auth::Error] unless the URL uses an http/https scheme
      def parse_http_uri!(url, label)
        uri = URI.parse(url.to_s)
        return uri if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        raise Legate::Auth::Error, "#{label} must use http or https scheme"
      end

      # @return [Array<String>] resolved IP strings ([] when resolution fails —
      #   the caller treats empty as a hard failure / fail-closed).
      def resolved_ips(hostname)
        [IPAddr.new(hostname).to_s]
      rescue IPAddr::InvalidAddressError
        begin
          Resolv.getaddresses(hostname)
        rescue Resolv::ResolvError
          []
        end
      end

      def restricted?(ip)
        # Normalize IPv4-mapped IPv6 (e.g. ::ffff:127.0.0.1) to its IPv4 form so
        # the loopback/private/link-local checks aren't bypassed by the mapping.
        ip = ip.native if ip.ipv4_mapped?
        ip.loopback? || ip.link_local? || ip.private? || BLOCKED_RANGES.any? { |r| r.include?(ip) }
      end
    end
  end
end
