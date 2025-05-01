# File: lib/adk/tools/base/http_client.rb
# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative '../../errors'
require_relative '../../version'

module ADK
  module Tools
    module Base
      # A mixin module providing standardized methods for making HTTP requests
      # within ADK tools.
      #
      # It uses the Faraday gem for HTTP requests and provides helpers for common
      # operations like GET, POST, and JSON parsing, along with standardized
      # error handling.
      module HttpClient
        # Default timeout values in seconds
        DEFAULT_TIMEOUT = 5
        DEFAULT_OPEN_TIMEOUT = 2

        protected

        # Initializes the Faraday HTTP client instance.
        # Should be called by the including tool, typically in its `initialize` method.
        #
        # @param base_url [String] The base URL for the API.
        # @param headers [Hash] Default headers to include in every request (merged with defaults).
        # @param timeout [Integer] Read timeout in seconds.
        # @param open_timeout [Integer] Connection open timeout in seconds.
        # @param client_options [Hash] Additional options passed directly to Faraday.new.
        # @param middleware_block [Proc] A block to configure Faraday middleware.
        # @return [void]
        # @raise [ADK::ToolError] If Faraday initialization fails.
        def setup_http_client(base_url:, headers: {}, timeout: DEFAULT_TIMEOUT, open_timeout: DEFAULT_OPEN_TIMEOUT,
                              client_options: {}, &middleware_block)
          default_headers = {
            'User-Agent' => "ADK-Ruby Tool/#{ADK::VERSION}"
          }
          merged_headers = default_headers.merge(headers)

          ADK.logger.debug("Setting up HTTP client for #{self.class.name} with base URL: #{base_url}")
          @http_client = Faraday.new(url: base_url, headers: merged_headers, **client_options) do |faraday|
            # Default middleware
            faraday.adapter Faraday.default_adapter
            faraday.response :raise_error # Raise exceptions for HTTP 4xx/5xx responses
            faraday.request :url_encoded # Encode request params

            # Allow custom middleware configuration
            middleware_block&.call(faraday)

            # Set timeouts
            faraday.options.timeout = timeout
            faraday.options.open_timeout = open_timeout
          end
        rescue Faraday::Error => e
          err_msg = "Failed to initialize Faraday connection for #{self.class.name}: #{e.message}"
          ADK.logger.error(err_msg)
          @http_client = nil # Ensure client is nil if setup fails
          raise ADK::ToolError, err_msg
        end

        # Performs an HTTP GET request.
        #
        # @param path [String] The path to append to the base URL.
        # @param params [Hash] Query parameters for the request.
        # @param headers [Hash] Additional headers for this specific request.
        # @return [Faraday::Response] The response object.
        # @raise [ADK::ToolError] If the client is not initialized or if a network/HTTP error occurs.
        def http_get(path, params: {}, headers: {})
          make_http_request(:get, path, params: params, headers: headers)
        end

        # Performs an HTTP POST request.
        #
        # @param path [String] The path to append to the base URL.
        # @param body [Hash, String] The request body.
        # @param headers [Hash] Additional headers for this specific request (e.g., 'Content-Type').
        # @return [Faraday::Response] The response object.
        # @raise [ADK::ToolError] If the client is not initialized or if a network/HTTP error occurs.
        def http_post(path, body: nil, headers: {})
          make_http_request(:post, path, body: body, headers: headers)
        end

        # Parses the body of a Faraday::Response as JSON.
        #
        # @param response [Faraday::Response] The response object whose body needs parsing.
        # @return [Hash, Array] The parsed JSON data.
        # @raise [ADK::ToolError] If JSON parsing fails.
        def parse_json_response(response)
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          err_msg = "Error parsing JSON response: #{e.message}"
          ADK.logger.error(err_msg)
          ADK.logger.debug("Invalid JSON received: #{response.body.inspect}") # Log the problematic body
          raise ADK::ToolError, err_msg
        end

        private

        # Centralized method for making HTTP requests and handling common errors.
        #
        # @param method [Symbol] The HTTP method (:get, :post, etc.).
        # @param path [String] The request path.
        # @param params [Hash] URL query parameters.
        # @param body [Hash, String, nil] Request body.
        # @param headers [Hash] Request headers.
        # @return [Faraday::Response] The Faraday response object.
        # @raise [ADK::ToolError] If the client is not initialized or if errors occur.
        def make_http_request(method, path, params: {}, body: nil, headers: {})
          raise ADK::ToolError,
                "HTTP client has not been initialized. Call setup_http_client first." unless @http_client

          # Automatically encode body as JSON if it's a Hash and Content-Type suggests JSON
          request_body = body
          content_type = headers.transform_keys { |k|
            k.downcase
          }['content-type'] || @http_client.headers['Content-Type']
          if body.is_a?(Hash) && content_type&.include?('application/json')
            begin
              request_body = JSON.generate(body)
            rescue JSON::GeneratorError => e
              raise ADK::ToolError, "Failed to encode request body as JSON: #{e.message}"
            end
          end

          ADK.logger.info("Making HTTP #{method.to_s.upcase} request to path: #{path} with params: #{params}")
          ADK.logger.debug("Request Body: #{request_body.inspect}") if request_body
          ADK.logger.debug("Request Headers: #{headers.inspect}")

          begin
            # Pass the potentially encoded request_body
            response = @http_client.run_request(method, path, request_body, headers) do |req|
              req.params.update(params) if params.any?
            end
            ADK.logger.info("Received HTTP response: Status #{response.status}")
            ADK.logger.debug("Response Body: #{response.body.inspect}")
            response
          rescue Faraday::TimeoutError => e
            err_msg = "Timeout during #{method.to_s.upcase} request to #{path}: #{e.message}"
            ADK.logger.error(err_msg)
            raise ADK::ToolError, err_msg
          rescue Faraday::ConnectionFailed => e
            err_msg = "Connection failed during #{method.to_s.upcase} request to #{path}: #{e.message}"
            ADK.logger.error(err_msg)
            raise ADK::ToolError, err_msg
          rescue Faraday::Error => e # Catches other Faraday errors, including 4xx/5xx via :raise_error middleware
            status_code = e.response[:status] if e.response
            err_msg = "HTTP error during #{method.to_s.upcase} request to #{path} (Status: #{status_code || 'N/A'}): #{e.message}"
            ADK.logger.error(err_msg)
            ADK.logger.debug("Error Response Body: #{e.response[:body].inspect}") if e.response && e.response[:body]
            raise ADK::ToolError, err_msg
          rescue StandardError => e # Catch any other unexpected errors
            err_msg = "Unexpected error during #{method.to_s.upcase} request to #{path}: #{e.class} - #{e.message}"
            ADK.logger.error(err_msg)
            ADK.logger.error(e.backtrace.first(5).join("\n"))
            raise ADK::ToolError, err_msg
          end
        end
      end # module HttpClient
    end # module Base
  end # module Tools
end # module ADK
