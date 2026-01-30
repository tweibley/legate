# frozen_string_literal: true

require 'resolv'
require 'ipaddr'
require_relative 'errors'

module ADK
  # Utility module for security-related functions.
  module SecurityUtils
    module_function

    # Validates that the target host is not a private, loopback, or link-local address (SSRF protection).
    #
    # @param hostname [String] The hostname or IP address to validate.
    # @raise [ADK::SecurityError] If the host resolves to a restricted IP address.
    # @raise [ADK::SecurityError] If the hostname cannot be resolved.
    def validate_url_security(hostname)
      # Resolve hostname to IPs (handles both IPv4 and IPv6)
      begin
        ips = Resolv.getaddresses(hostname)
      rescue Resolv::ResolvError => e
        raise ADK::SecurityError, "Could not resolve hostname: #{hostname}", cause: e
      end

      # If no IPs found (rare if no error raised), treat as error
      raise ADK::SecurityError, "Could not resolve hostname: #{hostname}" if ips.empty?

      ips.each do |ip_str|
        begin
          ip = IPAddr.new(ip_str)
          if ip.loopback? || ip.link_local? || ip.private? || ip.to_s == '0.0.0.0'
            raise ADK::SecurityError, "Security Error: Blocked access to restricted network address #{ip_str} (#{hostname})"
          end
        rescue IPAddr::InvalidAddressError
          # If we can't parse the IP, we should probably be safe and block it.
          raise ADK::SecurityError, "Security Error: Invalid IP address resolved: #{ip_str}"
        end
      end
    end
  end
end
