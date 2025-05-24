# File: lib/adk/auth/schemes/http_bearer.rb
# frozen_string_literal: true

require_relative '../scheme'
require_relative '../error'
require_relative '../credential'
require_relative '../exchanged_credential'

module ADK
  module Auth
    module Schemes
      # HTTP Bearer authentication scheme.
      # This scheme applies a bearer token to requests via the Authorization header.
      class HTTPBearer < Scheme
        # Get the type of authentication scheme
        # @return [Symbol] The scheme type identifier
        def scheme_type
          :http_bearer
        end
        
        # Apply authentication to a request
        # @param request [Hash] The request hash to modify
        # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential to use
        # @return [Hash] The modified request with authentication applied
        # @raise [ADK::Auth::Error] If the bearer token cannot be applied
        def apply_to_request(request, credential)
          # Create a deep copy of the request to avoid modifying the original
          request_copy = Marshal.load(Marshal.dump(request))
          
          # Handle the case where we get a stack object from Excon
          if request_copy.is_a?(Hash)
            if request_copy[:stack]
              # Extract the data from stack (Excon middleware format)
              [:scheme, :method, :path, :host, :port, :query].each do |key|
                if request_copy[:stack][key] && !request_copy[key]
                  request_copy[key] = request_copy[:stack][key]
                end
              end
            end
            
            # Ensure headers hash exists
            request_copy[:headers] ||= {}
          end
          
          # Extract the bearer token from the credential
          bearer_token = extract_bearer_token(credential)
          raise ADK::Auth::Error, 'Bearer token not found in credential' unless bearer_token
          
          # Apply the bearer token to the Authorization header
          request_copy[:headers]['Authorization'] = "Bearer #{bearer_token}"
          request_copy
        end
        
        # Exchange a credential for a token
        # @param credential [ADK::Auth::Credential] The credential to exchange
        # @return [ADK::Auth::ExchangedCredential] The exchanged token
        def exchange_token(credential)
          # For bearer tokens, we simply create a "token" that wraps the bearer token
          # This is useful for token management consistency
          bearer_token = extract_bearer_token(credential)
          raise ADK::Auth::TokenExchangeError, 'Bearer token not found in credential' unless bearer_token
          
          # Create a simple exchanged credential that never expires
          ADK::Auth::ExchangedCredential.new(
            auth_type: :http_bearer,
            access_token: bearer_token
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
        
        # Extract the bearer token from a credential
        # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential
        # @return [String, nil] The bearer token or nil if not found
        def extract_bearer_token(credential)
          # First try bearer_token
          return credential[:bearer_token] if credential[:bearer_token]
          
          # Next try access_token
          return credential[:access_token] if credential[:access_token]
          
          # Finally try token
          credential[:token]
        end
      end

      # Alias HTTPBearer as HttpBearer for backward compatibility
      HttpBearer = HTTPBearer
    end
  end
end 