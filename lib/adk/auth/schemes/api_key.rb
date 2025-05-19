# File: lib/adk/auth/schemes/api_key.rb
# frozen_string_literal: true

require_relative '../scheme'
require_relative '../error'
require_relative '../exchanged_credential'

module ADK
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
        # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential to use
        # @return [Hash] The modified request with authentication applied
        # @raise [ADK::Auth::Error] If the API key cannot be applied
        def apply_to_request(request, credential)
          # Extract the API key from the credential
          api_key = extract_api_key(credential)
          raise ADK::Auth::Error, 'API key not found in credential' unless api_key
          
          # Get parameters for applying the API key
          location = credential[:location] || 'header'
          name = credential[:name] || DEFAULT_HEADER_NAME
          
          # Apply the API key based on location
          case location.to_s.downcase
          when 'header'
            apply_to_header(request, name, api_key)
          when 'query', 'querystring'
            apply_to_query(request, name, api_key)
          when 'cookie'
            apply_to_cookie(request, name, api_key)
          else
            raise ADK::Auth::Error, "Unsupported API key location: #{location}"
          end
        end
        
        # Exchange a credential for a token
        # @param credential [ADK::Auth::Credential] The credential to exchange
        # @return [ADK::Auth::ExchangedCredential] The exchanged token
        def exchange_token(credential)
          # For API keys, we simply create a "token" that wraps the API key
          # This is useful for token management consistency
          api_key = extract_api_key(credential)
          raise ADK::Auth::TokenExchangeError, 'API key not found in credential' unless api_key
          
          # Create a simple exchanged credential that never expires
          ADK::Auth::ExchangedCredential.new(
            auth_type: :api_key,
            api_key: api_key,
            location: credential[:location] || 'header',
            name: credential[:name] || DEFAULT_HEADER_NAME
          )
        end
        
        private
        
        # Extract the API key from a credential
        # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential
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
          # Parse the URL
          uri = URI(request[:url])
          
          # Parse existing query parameters
          params = URI.decode_www_form(uri.query || '')
          
          # Add or replace the API key parameter
          found = false
          params.map! do |key, value|
            if key == name
              found = true
              [name, api_key]
            else
              [key, value]
            end
          end
          
          # Add the parameter if it wasn't found
          params << [name, api_key] unless found
          
          # Update the URI with new query string
          uri.query = URI.encode_www_form(params)
          
          # Update the request URL
          request[:url] = uri.to_s
          request
        end
        
        # Apply the API key to a request cookie
        # @param request [Hash] The request to modify
        # @param name [String] The cookie name
        # @param api_key [String] The API key
        # @return [Hash] The modified request
        def apply_to_cookie(request, name, api_key)
          request[:headers] ||= {}
          
          # Parse existing cookies if any
          cookies = []
          if request[:headers]['Cookie']
            cookies = request[:headers]['Cookie'].split('; ')
          end
          
          # Add or replace our cookie
          cookie_found = false
          cookies.map! do |cookie|
            if cookie.start_with?("#{name}=")
              cookie_found = true
              "#{name}=#{api_key}"
            else
              cookie
            end
          end
          
          # Add cookie if not found
          cookies << "#{name}=#{api_key}" unless cookie_found
          
          # Update request with new cookies
          request[:headers]['Cookie'] = cookies.join('; ')
          request
        end
      end
    end
  end
end 