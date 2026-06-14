# File: lib/legate/auth/schemes/api_key.rb
# frozen_string_literal: true

require_relative '../scheme'
require_relative '../error'
require_relative '../exchanged_credential'

module Legate
  module Auth
    module Schemes
      # API Key authentication scheme.
      # This scheme applies an API key to requests via a header, query parameter, or cookie.
      class ApiKey < Scheme
        # Default header name for API key authentication
        DEFAULT_HEADER_NAME = 'X-API-Key'

        # Get the type of authentication scheme
        # @return [Symbol] The scheme type identifier
        def scheme_type
          :api_key
        end

        # Apply authentication to a request
        # @param request [Hash] The request hash to modify
        # @param credential [Legate::Auth::Credential, Legate::Auth::ExchangedCredential] The credential to use
        # @return [Hash] The modified request with authentication applied
        # @raise [Legate::Auth::Error] If the API key cannot be applied
        def apply_to_request(request, credential)
          # Create a deep copy of the request to avoid modifying the original
          request_copy = Marshal.load(Marshal.dump(request))

          # Handle the case where we get a stack object from Excon
          if request_copy.is_a?(Hash)
            if request_copy[:stack]
              # Extract the data from stack (Excon middleware format)
              %i[scheme method path host port query].each do |key|
                request_copy[key] = request_copy[:stack][key] if request_copy[:stack][key] && !request_copy[key]
              end
            end

            # Ensure headers hash exists
            request_copy[:headers] ||= {}
          end

          # Extract the API key from the credential
          api_key = extract_api_key(credential)
          raise Legate::Auth::Error, 'API key not found in credential' unless api_key

          # Get parameters for applying the API key
          location = credential[:location] || 'header'
          name = credential[:name] || DEFAULT_HEADER_NAME

          # Apply the API key based on location
          case location.to_s.downcase
          when 'header'
            apply_to_header(request_copy, name, api_key)
          when 'query', 'querystring'
            apply_to_query(request_copy, name, api_key)
          when 'cookie'
            apply_to_cookie(request_copy, name, api_key)
          else
            raise Legate::Auth::Error, "Unsupported API key location: #{location}"
          end
        end

        # Exchange a credential for a token
        # @param credential [Legate::Auth::Credential] The credential to exchange
        # @return [Legate::Auth::ExchangedCredential] The exchanged token
        def exchange_token(credential)
          # For API keys, we simply create a "token" that wraps the API key
          # This is useful for token management consistency
          api_key = extract_api_key(credential)
          raise Legate::Auth::TokenExchangeError, 'API key not found in credential' unless api_key

          # Create a simple exchanged credential that never expires
          Legate::Auth::ExchangedCredential.new(
            auth_type: :api_key,
            api_key: api_key,
            location: credential[:location] || 'header',
            name: credential[:name] || DEFAULT_HEADER_NAME
          )
        end

        # Get hash representation of the scheme
        # @return [Hash] Scheme configuration as a hash
        def to_h
          {
            type: scheme_type
          }
        end

        private

        # Extract the API key from a credential
        # @param credential [Legate::Auth::Credential, Legate::Auth::ExchangedCredential] The credential
        # @return [String, nil] The API key or nil if not found
        def extract_api_key(credential)
          # First try api_key
          return credential[:api_key] if credential[:api_key]

          # Next try key
          return credential[:key] if credential[:key]

          # Finally try token
          credential[:token]
        end

        # Apply the API key to a request header
        # @param request [Hash] The request to modify
        # @param name [String] The header name
        # @param api_key [String] The API key
        # @return [Hash] The modified request
        def apply_to_header(request, name, api_key)
          validate_header_value!(api_key, 'API key')
          validate_header_value!(name, 'Header name')
          request[:headers] ||= {}
          request[:headers][name] = api_key
          request
        end

        # Apply the API key to a request query parameter
        # @param request [Hash] The request to modify
        # @param name [String] The parameter name
        # @param api_key [String] The API key
        # @return [Hash] The modified request
        def apply_to_query(request, name, api_key)
          # Initialize headers if not present
          request[:headers] ||= {}

          # The proper way to handle query parameters depends on the format
          # expected by the HTTP client library

          # Handle simple URL case
          if request[:url]
            # Properly append the query parameter
            separator = request[:url].include?('?') ? '&' : '?'
            request[:url] = "#{request[:url]}#{separator}#{name}=#{api_key}"
          end

          # Handle query param hash (used by Excon and other libraries)
          if request[:query].is_a?(Hash)
            # Simply add the param to the hash
            request[:query][name] = api_key
          elsif request[:query].is_a?(String)
            # Append to existing query string
            separator = request[:query].empty? ? '' : '&'
            request[:query] = "#{request[:query]}#{separator}#{name}=#{api_key}"
          elsif request[:query].nil?
            # Create a new query hash
            request[:query] = { name => api_key }
          end

          # Also update the URL with query parameters for debugging
          if !request[:url] && (request[:scheme] || request[:host] || request[:path])
            # Build the URL from components for reference
            scheme = request[:scheme] || 'https'
            host = request[:host] || 'example.com'
            path = request[:path] || '/'
            port = request[:port]

            # Construct URL from components
            port_part = port ? ":#{port}" : ''
            url = "#{scheme}://#{host}#{port_part}#{path}"

            # Add query string if present
            if request[:query]
              query_str = if request[:query].is_a?(Hash)
                            params = []
                            request[:query].each do |k, v|
                              params << "#{k}=#{v}"
                            end
                            params.join('&')
                          else
                            request[:query].to_s
                          end

              url += "?#{query_str}" unless query_str.empty?
            end

            request[:url] = url
          end

          request
        end

        # Apply the API key to a request cookie
        # @param request [Hash] The request to modify
        # @param name [String] The cookie name
        # @param api_key [String] The API key
        # @return [Hash] The modified request
        def apply_to_cookie(request, name, api_key)
          validate_header_value!(api_key, 'API key (cookie)')
          validate_header_value!(name, 'Cookie name')
          # Initialize headers if not present
          request[:headers] ||= {}

          # Construct the cookie
          cookie_value = "#{name}=#{api_key}"

          # Append to existing cookie or set new one
          request[:headers]['Cookie'] = if request[:headers]['Cookie'] && !request[:headers]['Cookie'].empty?
                                          "#{request[:headers]['Cookie']}; #{cookie_value}"
                                        else
                                          cookie_value
                                        end

          request
        end
      end
    end
  end
end
