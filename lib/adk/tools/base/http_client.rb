# File: lib/adk/tools/base/http_client.rb
# frozen_string_literal: true

require 'excon'
require 'json'
require 'uri' # For URI.join

require_relative '../../tool/error' # Use the errors defined in Step 2
require_relative '../../version'

module ADK
  module Tools
    module Base
      # Mixin module providing standardized, reusable HTTP client capabilities
      # for ADK tools, built upon the Excon gem.
      #
      # Include this module in your Tool class and call `setup_http_client`
      # in your `initialize` method.
      #
      # It offers helper methods (http_get, http_post, etc.) for common requests,
      # handles base URL joining, JSON encoding/decoding (optional), logging,
      # and wraps Excon errors into standardized ADK::ToolError subclasses.
      module HttpClient
        attr_reader :http_client
        attr_reader :http_base_url

        # Make request helpers public API for tools including this module
        public

        def http_get(path, query: {}, headers: {}, options: {})
          make_request(:get, path, query: query, headers: headers, options: options)
        end

        def http_post(path, body: nil, query: {}, headers: {}, options: {})
          make_request(:post, path, body: body, query: query, headers: headers, options: options)
        end

        def http_put(path, body: nil, query: {}, headers: {}, options: {})
          make_request(:put, path, body: body, query: query, headers: headers, options: options)
        end

        def http_delete(path, query: {}, headers: {}, options: {})
          make_request(:delete, path, query: query, headers: headers, options: options)
        end

        protected

        # Initializes the Excon HTTP client instance.
        # Should be called by the including tool, typically in its `initialize` method.
        # Stores the connection instance in `@http_client` and base URL in `@http_base_url`.
        #
        # @param base_url [String] The base URL for the API. Must be a valid URI string.
        # @param headers [Hash] Default headers to include in every request (merged with defaults).
        # @param options [Hash] Options passed directly to `Excon.new`. See Excon documentation for available options
        #   (e.g., :read_timeout, :write_timeout, :connect_timeout, :persistent, :proxy, :ssl_verify_peer).
        #   Allows overriding the default instrumentor via `:instrumentor` key.
        # @return [void]
        # @raise [ADK::ToolError] If the base_url is invalid or Excon initialization fails.
        def setup_http_client(base_url:, headers: {}, options: {})
          # Revert: base_url is required again
          begin
            @http_base_url = URI.parse(base_url.to_s)
            unless @http_base_url.is_a?(URI::HTTP) || @http_base_url.is_a?(URI::HTTPS)
              raise URI::InvalidURIError, "Scheme must be http or https"
            end
          rescue URI::InvalidURIError => e
            raise ADK::ToolError, "Invalid base_url provided: #{base_url} - #{e.message}", cause: e
          end

          default_user_agent = "ADK-Ruby/#{ADK::VERSION} #{Excon::USER_AGENT}"
          default_headers = { 'User-Agent' => default_user_agent }
          merged_headers = default_headers.merge(headers)
          default_options = { persistent: true, connect_timeout: 5, read_timeout: 15, write_timeout: 15,
                              instrumentor: Excon::LoggingInstrumentor }
          final_options = default_options.merge(options)
          final_options[:headers] = merged_headers unless merged_headers.empty?
          if final_options[:instrumentor] == Excon::LoggingInstrumentor && defined?(ADK.logger)
            final_options[:instrumentor_params] = { logger: ADK.logger }
          end

          # Store connection options for potential use in make_request for absolute URLs
          @http_connection_options = final_options.dup

          begin
            log_options_for_debug = final_options.dup
            log_options_for_debug[:headers] = '[REDACTED]' unless ADK.logger.level == Logger::DEBUG
            ADK.logger.debug("Setting up Excon client for #{self.class.name} with base URL: #{@http_base_url}")
            ADK.logger.debug("Excon options: #{log_options_for_debug}")

            # Create connection using the (mandatory) base URL
            @http_client = Excon.new(@http_base_url.to_s, final_options)

            # Store default *request* options and headers separately
            @http_default_request_options = final_options.reject { |k, _|
              [:headers, :instrumentor, :instrumentor_params].include?(k)
            }
            @http_default_headers = merged_headers
          rescue Excon::Error::Socket => e
            err_msg = "Failed to initialize Excon connection for #{self.class.name} to #{@http_base_url}: #{e.message}"
            ADK.logger.error(err_msg)
            @http_client = nil
            raise ADK::ToolNetworkError, err_msg, cause: e
          rescue StandardError => e
            err_msg = "Unexpected error initializing Excon for #{self.class.name}: #{e.class} - #{e.message}"
            ADK.logger.error(err_msg)
            @http_client = nil
            raise ADK::ToolError, err_msg, cause: e
          end
        end

        # TODO: Add any private helper methods if needed

        private

        # Centralized method for making HTTP requests and handling common errors/wrapping.
        def make_request(method, path, body: nil, query: {}, headers: {}, options: {})
          begin
            # Ensure setup was called, but @http_client might not be used if path is absolute
            raise ADK::ToolError,
                  'HTTP client options not initialized. Call setup_http_client first.' unless @http_connection_options
            raise ADK::ToolError, 'Base URL not set properly during setup.' unless @http_base_url

            request_params = @http_default_request_options.merge(options)
            request_params[:method] = method

            target_uri = nil
            is_absolute = false
            begin
              # Try parsing path as an absolute URI first
              parsed_path = URI.parse(path.to_s)
              if parsed_path.is_a?(URI::HTTP) || parsed_path.is_a?(URI::HTTPS)
                target_uri = parsed_path
                is_absolute = true
              else
                # Assume relative path, join with base
                target_uri = URI.join(@http_base_url, path)
              end

              # Path/Query setup differs slightly for absolute vs relative
              if is_absolute
                # For absolute URLs, the full path/query is part of target_uri
                # We don't need to set host/scheme/port in request_params
                # as Excon.new will use the full target_uri.to_s
                request_params[:path] = target_uri.request_uri # Path + Query
              else
                # For relative URLs, use the persistent client and set path/query
                request_params[:path] = target_uri.request_uri # Path + Query (relative to base)
              end

              # Merge explicit query params with any existing in the URI
              uri_query = URI.decode_www_form(target_uri.query || '').to_h
              final_query = uri_query.merge(query)
              request_params[:query] = final_query unless final_query.empty?
              # Update path if query was added/changed (remove original query part if exists)
              request_params[:path] = target_uri.path
            rescue URI::InvalidURIError => e
              raise ADK::ToolError, "Invalid URL or path provided: #{path} - #{e.message}", cause: e
            end

            # 3. Merge Headers
            request_params[:headers] = @http_default_headers.merge(headers)

            # Determine if Content-Type was explicitly passed
            custom_content_type_provided = headers.keys.any? { |k| k.to_s.casecmp('Content-Type').zero? }
            content_type_key = request_params[:headers].keys.find { |k|
              k.to_s.casecmp('Content-Type').zero?
            } || 'Content-Type'

            # 4. Handle Request Body and Content-Type logic
            if body.is_a?(Hash) && [:post, :put, :patch].include?(method)
              # Only default to application/json if Content-Type was not explicitly provided
              unless custom_content_type_provided
                request_params[:headers][content_type_key] = 'application/json; charset=utf-8'
              end
              # Get the final effective content type for encoding check
              final_content_type = request_params[:headers].find { |k, _| k.to_s.casecmp('Content-Type').zero? }&.last

              if final_content_type&.start_with?('application/json')
                # ... JSON encode body ...
                begin
                  request_params[:body] = JSON.generate(body)
                rescue JSON::GeneratorError => e
                  # raise ADK::ToolError, "Failed to encode request body as JSON: #{e.message}" # No cause
                  # Add cause for better debugging
                  raise ADK::ToolError, "Failed to encode request body as JSON: #{e.message}", cause: e
                end
              else
                # ... Handle Hash body with non-JSON CT ...
                ADK.logger.warn "Sending Hash body with non-JSON Content-Type (#{final_content_type}) for #{target_uri}"
                request_params[:body] = body
              end
            elsif body # Body is not a Hash (likely a String)
              request_params[:body] = body
              # If body is string AND Content-Type wasn't explicitly passed, remove the default one.
              unless custom_content_type_provided
                key_to_delete = request_params[:headers].keys.find { |k| k.to_s.casecmp('Content-Type').zero? }
                request_params[:headers].delete(key_to_delete) if key_to_delete
              end
            end

            # 5. Execute Request: Choose client based on absolute vs relative path
            ADK.logger.info "Executing HTTP #{method.to_s.upcase} request to #{target_uri}"

            response = nil
            if is_absolute
              ADK.logger.debug "Using temporary Excon client for absolute URL: #{target_uri}"

              # Prepare options for the temporary Excon client instance
              temp_client_options = @http_connection_options.reject { |k, _| k == :headers }
              # Deep duplicate headers hash to avoid modifying the original
              final_headers_for_new = Marshal.load(Marshal.dump(@http_connection_options[:headers] || {}))
              # Merge the fully processed request_params[:headers] (which includes defaults and customs)
              final_headers_for_new.merge!(request_params[:headers].transform_keys(&:to_s))
              temp_client_options[:headers] = final_headers_for_new

              temp_client = Excon.new(target_uri.to_s, temp_client_options)

              # Prepare the params for the .request call (method, body, query, etc., NO headers)
              request_params_for_absolute = request_params.reject { |k, _| k == :headers }

              ADK.logger.debug "Excon Temp Request Params (for .request call): #{request_params_for_absolute.inspect}"
              ADK.logger.debug "Excon Temp Client Options (for .new call): #{temp_client_options.inspect}"
              response = temp_client.request(request_params_for_absolute)
            else
              ADK.logger.debug "Using persistent Excon client for relative path: #{target_uri}"
              # Use the persistent client setup with the base URL
              raise ADK::ToolError, 'Persistent HTTP client not initialized.' unless @http_client

              ADK.logger.debug "Excon Persistent Request Params: #{request_params.inspect}"
              response = @http_client.request(request_params)
            end

            ADK.logger.info "Received HTTP response: Status #{response.status}"
            ADK.logger.debug "Response Body: #{response.body[0..500]}..."

            unless (200..299).cover?(response.status)
              err_msg = "HTTP Error: Received status #{response.status} for #{method.to_s.upcase} #{target_uri}"
              ADK.logger.error(err_msg)
              raise Excon::Error::HTTPStatus.new(err_msg, nil, response)
            end

            response

          # Step 7: Error Wrapping Logic
          rescue Excon::Error::Timeout => e
            err_msg = "Timeout during #{method.to_s.upcase} request to #{target_uri || path}: #{e.message}"
            ADK.logger.error(err_msg)
            raise ADK::ToolTimeoutError, err_msg, cause: e
          rescue Excon::Error::Socket => e
            err_msg = "Network/Socket error during #{method.to_s.upcase} request to #{target_uri || path}: #{e.message}"
            ADK.logger.error(err_msg)
            raise ADK::ToolNetworkError, err_msg, cause: e
          rescue Excon::Error::Certificate => e
            err_msg = "SSL Certificate error during #{method.to_s.upcase} request to #{target_uri || path}: #{e.message}"
            ADK.logger.error(err_msg)
            raise ADK::ToolCertificateError, err_msg, cause: e
          rescue Excon::Error::HTTPStatus => e
            status = e.response&.status || 'N/A'
            body_preview = e.response&.body&.slice(0, 500)
            err_msg = "HTTP Error: Received status #{status} for #{method.to_s.upcase} #{target_uri || path}"
            ADK.logger.error("#{err_msg} - Response Body: #{body_preview}...")
            raise ADK::ToolHttpError.new(err_msg, response: e.response, cause: e)
          rescue Excon::Error => e
            status = e.respond_to?(:response) && e.response ? e.response.status : 'N/A'
            err_msg = "Excon error during #{method.to_s.upcase} request to #{target_uri || path} (Status: #{status}): #{e.class} - #{e.message}"
            ADK.logger.error(err_msg)
            raise ADK::ToolError, err_msg, cause: e
          # Catch ADK::ToolError explicitly first to prevent re-wrapping
          rescue ADK::ToolError => e
            raise e
          # Catch StandardError last, covering errors during setup (like URI.join, JSON.generate if not caught above)
          rescue StandardError => e
            # Avoid re-wrapping ADK::ToolErrors that might bubble up (e.g., from URI.join failure)
            # raise if e.is_a?(ADK::ToolError) # Handled by the rescue above now

            # Make error message generation safer but include original message
            error_class_name = e.class.name rescue 'UnknownError'
            error_message = e.message rescue 'No message available'
            err_msg = "Unexpected error during #{method.to_s.upcase} request logic: #{error_class_name} - #{error_message}"
            ADK.logger.error(err_msg)
            # Safely log backtrace if available - REMOVED as it might cause issues with already wrapped ADK::ToolErrors
            # Raise without cause for StandardError as it can cause issues
            raise ADK::ToolError, err_msg
          end
        end
      end # module HttpClient
    end # module Base
  end # module Tools
end # module ADK
