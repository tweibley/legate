# File: lib/legate/tools/http_request_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative 'base/http_client'
require_relative 'base/safe_url'

module Legate
  module Tools
    # General-purpose HTTP client tool.
    #
    # Makes a request to a URL and returns the status code, response headers, and
    # body. It is SSRF-safe (private/loopback/link-local hosts are blocked and the
    # connection is pinned to the validated IP) and auth-aware (configured auth
    # URL-mappings are applied automatically; pass `headers` for manual auth).
    #
    # A non-2xx response is returned as a normal result (with its status_code) so
    # an agent can inspect it; only network/SSRF/timeout failures are errors.
    class HttpRequest < Legate::Tool
      include Legate::Tools::Base::HttpClient

      # Cap the returned body so a large download can't blow up the context/LLM.
      MAX_BODY_BYTES = 1_000_000
      ALLOWED_METHODS = %w[GET POST PUT PATCH DELETE HEAD].freeze

      tool_name # inferred: :http_request
      tool_description 'Makes an HTTP request to a URL and returns the status code, headers, and body. ' \
                       'Supports GET (default), POST, PUT, PATCH, DELETE, and HEAD. Blocks private and ' \
                       'loopback addresses (SSRF-safe) and applies configured authentication for matching URLs.'

      parameter :url, type: :string, required: true,
                      description: 'The full URL to request (must be http or https).'
      parameter :method, type: :string, required: false,
                         description: 'HTTP method: GET (default), POST, PUT, PATCH, DELETE, or HEAD.'
      parameter :headers, type: :hash, required: false,
                          description: 'Optional request headers.'
      parameter :body, type: %i[hash string], required: false,
                       description: 'Optional request body. A Hash is JSON-encoded with Content-Type: application/json.'
      parameter :query, type: :hash, required: false,
                        description: 'Optional query-string parameters.'

      def initialize(**options)
        super(**options)
        # Targets are passed absolute per-request; the base URL is only a required placeholder.
        setup_http_client(base_url: 'https://placeholder.invalid')
      end

      private

      def perform_execution(params, context)
        url = params.fetch(:url)
        method = (params[:method] || 'GET').to_s.upcase
        return { status: :error, error_message: "Unsupported HTTP method: #{method}" } unless ALLOWED_METHODS.include?(method)

        uri, pinned_ip = Legate::Tools::Base::SafeUrl.resolve!(url)
        headers = apply_auth(context, method, url, stringify_headers(params[:headers] || {}))

        response = make_request(
          method.downcase.to_sym, url,
          body: params[:body],
          query: params[:query] || {},
          headers: headers,
          options: { resolved_ip: pinned_ip, original_host: uri.host }
        )
        { status: :success, result: build_result(url, response) }
      rescue Legate::ToolHttpError => e
        # A non-2xx response still completed; surface its details rather than erroring.
        return { status: :success, result: build_result(url, e.response) } if e.response

        { status: :error, error_message: e.message }
      rescue Legate::ToolError => e
        { status: :error, error_message: e.message }
      end

      # Let the execution context apply any configured auth (URL mappings). It is a
      # no-op when no auth is configured or the context doesn't support it.
      def apply_auth(context, method, url, headers)
        return headers unless context.respond_to?(:handle_request_auth)

        request = context.handle_request_auth({ method: method.downcase.to_sym, url: url, headers: headers })
        request.is_a?(Hash) && request[:headers] ? request[:headers] : headers
      rescue StandardError => e
        Legate.logger.warn("HttpRequest: auth application failed, sending unauthenticated: #{e.message}")
        headers
      end

      def build_result(url, response)
        body = response.body.to_s
        truncated = body.bytesize > MAX_BODY_BYTES
        body = body.byteslice(0, MAX_BODY_BYTES) if truncated
        {
          url: url,
          status_code: response.status,
          headers: response.headers,
          body: body,
          truncated: truncated
        }
      end

      def stringify_headers(hash)
        hash.transform_keys(&:to_s)
      end
    end
  end
end
