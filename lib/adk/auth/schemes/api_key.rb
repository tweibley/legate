# File: lib/adk/auth/schemes/api_key.rb
# frozen_string_literal: true

module ADK
  module Auth
    module Schemes
      # Implements API Key authentication
      # API Keys can be passed in headers, query parameters, or cookies
      class APIKey < ADK::Auth::Scheme
        # Valid locations for API keys
        VALID_LOCATIONS = %i[header query cookie].freeze
        
        # @return [Symbol] The location of the API key (header, query, cookie)
        attr_reader :location
        
        # @return [String] The name of the parameter or header
        attr_reader :name
        
        # Initialize a new API Key scheme
        # @param location [Symbol] Where to place the API key (header, query, cookie)
        # @param name [String] The name of the parameter or header
        # @param prefix [String, nil] Optional prefix for the key value
        def initialize(location: :header, name: 'X-Api-Key', prefix: nil)
          @location = location.to_sym
          @name = name
          @prefix = prefix
          validate!
        end
        
        # @return [Symbol] The scheme type
        def scheme_type
          :api_key
        end
        
        # Validates the scheme configuration
        # @raise [ADK::Auth::SchemeValidationError] If the configuration is invalid
        def validate!
          unless VALID_LOCATIONS.include?(@location)
            raise ADK::Auth::SchemeValidationError,
                  "Invalid API key location: #{@location}. Must be one of: #{VALID_LOCATIONS.join(', ')}"
          end
          
          unless @name && !@name.empty?
            raise ADK::Auth::SchemeValidationError, 'API key name cannot be empty'
          end
        end
        
        # Applies the API key to a request
        # @param request [Hash] The request to apply the API key to
        # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential with the API key
        # @return [Hash] The updated request
        # @raise [ADK::Auth::CredentialError] If the credential is missing the API key
        def apply_to_request(request, credential)
          api_key = get_api_key(credential)
          request = request.dup
          
          case @location
          when :header
            request[:headers] ||= {}
            request[:headers][@name] = format_api_key(api_key)
          when :query
            request[:query] ||= {}
            request[:query][@name] = format_api_key(api_key)
          when :cookie
            request[:headers] ||= {}
            request[:headers]['Cookie'] ||= ''
            request[:headers]['Cookie'] += '; ' unless request[:headers]['Cookie'].empty?
            request[:headers]['Cookie'] += "#{@name}=#{format_api_key(api_key)}"
          end
          
          request
        end
        
        # Convert to a hash
        # @return [Hash] A hash representation of the scheme
        def to_h
          super.merge(
            location: @location,
            name: @name,
            prefix: @prefix
          ).compact
        end
        
        private
        
        # Format the API key with an optional prefix
        # @param api_key [String] The raw API key
        # @return [String] The formatted API key
        def format_api_key(api_key)
          @prefix ? "#{@prefix}#{api_key}" : api_key
        end
        
        # Extract the API key from a credential
        # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential
        # @return [String] The API key
        # @raise [ADK::Auth::CredentialError] If the credential is missing the API key
        def get_api_key(credential)
          if credential.is_a?(ADK::Auth::Credential)
            # For initial credentials
            api_key = credential[:api_key, resolve_env: true]
          elsif credential.is_a?(ADK::Auth::ExchangedCredential)
            # For exchanged credentials (unlikely for API keys, but supported)
            api_key = credential[:api_key] || credential.access_token
          else
            api_key = nil
          end
          
          unless api_key && !api_key.empty?
            raise ADK::Auth::CredentialError, 'API key is missing from credential'
          end
          
          api_key
        end
      end
    end
  end
end 