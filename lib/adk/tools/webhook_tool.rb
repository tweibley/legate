# File: lib/adk/tools/webhook_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative 'base/http_client'
require 'openssl'
require 'json'
require 'uri'

module ADK
  module Tools
    # A tool for sending outgoing webhook requests (HTTP POST) from an agent.
    class WebhookTool < ADK::Tool
      include ADK::Tools::Base::HttpClient

      tool_name # Infer name from class: :webhook_tool
      tool_description 'Sends an HTTP POST request with a JSON payload to a specified webhook URL. Can optionally sign the request using HMAC-SHA256.'

      parameter :url, type: :string, required: true, description: 'The target webhook URL.'
      parameter :payload, type: [:hash, :string], required: true,
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
      # @param _context [ADK::ToolContext] The execution context (unused).
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
        rescue URI::InvalidURIError => e
          raise ADK::ToolArgumentError, "Invalid URL provided: #{target_url} - #{e.message}", cause: e
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
            raise ADK::ToolError, "Failed to encode payload as JSON: #{e.message}"
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
          ADK.logger.debug { "WebhookTool: Calculated signature: #{request_headers['X-Hub-Signature-256']}" }
        end

        ADK.logger.info("WebhookTool: Sending POST to #{target_url}")

        begin
          # Pass the custom headers; make_request adds defaults if needed
          response = make_request(:post, target_url, body: body_string, headers: request_headers)
          ADK.logger.info("WebhookTool: Received response status: #{response.status}")
          { status: :success, result: { response_status: response.status, response_body: response.body } }
        rescue ADK::ToolError => e
          ADK.logger.error("WebhookTool: Error sending webhook to #{target_url}: #{e.message}")
          raise
        end
      end
    end
  end
end
