# File: lib/legate/tools/webhook_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative 'base/http_client'
require 'openssl'
require 'json'
require 'uri'
require 'resolv'
require 'ipaddr'

module Legate
  module Tools
    # A tool for sending outgoing webhook requests (HTTP POST) from an agent.
    class WebhookTool < Legate::Tool
      include Legate::Tools::Base::HttpClient

      BLOCKED_RANGES = [
        IPAddr.new('0.0.0.0/8'),
        IPAddr.new('100.64.0.0/10')
      ].freeze
      DNS_RESOLVE_TIMEOUT = 5

      tool_name # Infer name from class: :webhook_tool
      tool_description 'Sends an HTTP POST request with a JSON payload to a specified webhook URL. Can optionally sign the request using HMAC-SHA256.'

      parameter :url, type: :string, required: true, description: 'The target webhook URL.'
      parameter :payload, type: %i[hash string], required: true,
                          description: 'The data payload to send. Hash payloads are automatically JSON-encoded with Content-Type: application/json.'
      parameter :secret, type: :string, required: false,
                         description: 'Optional secret key for calculating HMAC-SHA256 signature (X-Hub-Signature-256 header).'
      parameter :headers, type: :hash, required: false,
                          description: 'Optional custom headers to include (e.g., Content-Type for string payloads).'

      # Initializes the tool and the underlying HTTP client.
      def initialize(**options)
        super(**options)
        # Provide a dummy base_url, required by setup_http_client.
        # The actual target URL is provided absolute in perform_execution.
        setup_http_client(base_url: 'https://placeholder.invalid')
      end

      private

      # Executes the webhook POST request.
      # @param params [Hash] Tool parameters (:url, :payload, :secret, :headers).
      # @param _context [Legate::ToolContext] The execution context (unused).
      # @return [Hash] Result hash indicating success or error.
      def perform_execution(params, _context)
        target_url = params.fetch(:url)
        payload = params.fetch(:payload)
        secret = params[:secret]
        custom_headers = params[:headers] || {}

        # Validate URL early
        begin
          uri = URI.parse(target_url)
          raise URI::InvalidURIError, 'URL must be http or https' unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

          resolved_ip = validate_url_security(uri.host)
        rescue URI::InvalidURIError => e
          raise Legate::ToolArgumentError.new("Invalid URL provided: #{target_url} - #{e.message}", cause: e)
        end

        # Start with custom headers provided by the user
        request_headers = custom_headers.dup
        body_string = nil

        # Handle payload encoding
        if payload.is_a?(Hash)
          # Set Content-Type here as make_request receives a string
          request_headers['Content-Type'] ||= 'application/json; charset=utf-8'
          begin
            body_string = JSON.generate(payload)
          rescue JSON::GeneratorError => e
            raise Legate::ToolError, "Failed to encode payload as JSON: #{e.message}"
          end
        else
          body_string = payload.to_s
          # For string payload, *don't* set CT unless explicitly provided in custom_headers.
          # make_request will handle removing default CT if necessary.
        end

        # Calculate signature if secret is provided
        if secret
          signature = OpenSSL::HMAC.hexdigest('sha256', secret, body_string)
          request_headers['X-Hub-Signature-256'] = "sha256=#{signature}"
          Legate.logger.debug { "WebhookTool: Calculated signature: #{request_headers['X-Hub-Signature-256']}" }
        end

        Legate.logger.info("WebhookTool: Sending POST to #{target_url}")

        begin
          # Pass the custom headers; make_request adds defaults if needed
          response = make_request(:post, target_url, body: body_string, headers: request_headers,
                                                     options: { resolved_ip: resolved_ip, original_host: uri.host })
          Legate.logger.info("WebhookTool: Received response status: #{response.status}")
          { status: :success, result: { response_status: response.status, response_body: response.body } }
        rescue Legate::ToolError => e
          Legate.logger.error("WebhookTool: Error sending webhook to #{target_url}: #{e.message}")
          raise
        end
      end

      # Validates that the target host is not a private, loopback, or link-local address (SSRF protection).
      # Returns the first validated IP for connection pinning (prevents DNS rebinding TOCTOU).
      # @param hostname [String] The hostname or IP address to validate.
      # @return [String] First validated IP address to pin the connection to.
      # @raise [Legate::ToolArgumentError] If the host resolves to a restricted IP address.
      def validate_url_security(hostname)
        begin
          literal_ip = IPAddr.new(hostname)
          resolved_ips = [literal_ip.to_s]
        rescue IPAddr::InvalidAddressError
          resolved_ips = resolve_hostname(hostname)
        end

        raise Legate::ToolArgumentError, "Could not resolve hostname: #{hostname}" if resolved_ips.empty?

        resolved_ips.each do |ip_str|
          ip = IPAddr.new(ip_str)
          raise Legate::ToolArgumentError, "Security Error: Blocked access to restricted network address #{ip_str} (#{hostname})" if ip.loopback? || ip.link_local? || ip.private? || blocked_range?(ip)
        rescue IPAddr::InvalidAddressError
          raise Legate::ToolArgumentError, "Security Error: Invalid IP address resolved: #{ip_str}"
        end

        resolved_ips.first
      end

      def resolve_hostname(hostname)
        Resolv::DNS.open do |dns|
          dns.timeouts = DNS_RESOLVE_TIMEOUT
          a_records = dns.getresources(hostname, Resolv::DNS::Resource::IN::A)
          aaaa_records = dns.getresources(hostname, Resolv::DNS::Resource::IN::AAAA)
          (a_records + aaaa_records).map { |r| r.address.to_s }
        end
      rescue Resolv::ResolvError => e
        raise Legate::ToolArgumentError.new("Could not resolve hostname: #{hostname}", cause: e)
      end

      def blocked_range?(ip)
        BLOCKED_RANGES.any? { |range| range.include?(ip) }
      end
    end
  end
end
